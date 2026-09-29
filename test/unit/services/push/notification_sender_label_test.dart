import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/push/notification_sender_label.dart';

/// Row d9bc6f6c — WHO a notification is from, in its title.
///
/// The ruled mapping (Tiffany, 2026-09-28): persona → "🌻 Maya"; otherwise the
/// PROJECT alone; otherwise "Lupin".
void main() {
  group( "notificationSenderLabel — a persona wins", () {
    test( "icon and display name, in that order", () {
      // Shape per the captured wire sample,
      // test/fixtures/notifications/notification-with-persona.json.
      expect( notificationSenderLabel( <String, dynamic>{
        "id"            : "n-1",
        "sender_id"     : "claude.code@lupin-mobile.deepily.ai#a756441c",
        "voice_persona" : <String, dynamic>{
          "name"         : "Adam",
          "icon"         : "🌑",
          "display_name" : "Adam",
        },
      } ), "🌑 Adam" );
    } );

    test( "display_name is preferred over the allocation key", () {
      expect( notificationSenderLabel( <String, dynamic>{
        "voice_persona" : <String, dynamic>{
          "name"         : "maya",
          "display_name" : "Maya",
          "icon"         : "🌻",
        },
      } ), "🌻 Maya" );
    } );

    test( "a persona with no glyph yields just the name", () {
      expect( notificationSenderLabel( <String, dynamic>{
        "voice_persona" : <String, dynamic>{ "name": "Maya" },
      } ), "Maya" );
      expect( notificationSenderLabel( <String, dynamic>{
        "voice_persona" : <String, dynamic>{ "name": "Maya", "icon": "  " },
      } ), "Maya" );
    } );

    test( "a persona beats the project — it is the more useful name", () {
      expect( notificationSenderLabel( <String, dynamic>{
        "sender_id"     : "claude.code@lupin-mobile.deepily.ai#a756441c",
        "voice_persona" : <String, dynamic>{ "name": "Maya", "icon": "🌻" },
      } ), "🌻 Maya" );
    } );

    test( "a nameless or malformed persona falls through", () {
      for ( final persona in <dynamic>[
        <String, dynamic>{},
        <String, dynamic>{ "name": "" },
        <String, dynamic>{ "name": "   " },
        <String, dynamic>{ "icon": "🌻" },      // a glyph with nobody attached
        "Maya",                                  // not an object at all
        42,
      ] ) {
        expect( notificationSenderLabel( <String, dynamic>{
          "sender_id"     : "claude.code@lupin-mobile.deepily.ai#a756441c",
          "voice_persona" : persona,
        } ), "lupin-mobile", reason: "persona was $persona" );
      }
    } );
  } );

  group( "notificationSenderLabel — the project, WITHOUT the hash", () {
    test( "a sender id with no persona yields the project alone", () {
      // 🔴 THE HASH IS DROPPED ON PURPOSE. `#a756441c` is how the fleet tells two
      // seats of one project apart, and it is also eight hex characters nobody
      // reads off a lock screen (Tiffany: Rick cannot read a hash). Routing is
      // unaffected — the tap payload carries the FULL sender id.
      expect( notificationSenderLabel( <String, dynamic>{
        "sender_id" : "claude.code@lupin-mobile.deepily.ai#a756441c",
      } ), "lupin-mobile" );
    } );

    test( "an id with no hash still yields the project", () {
      expect( notificationSenderLabel( <String, dynamic>{
        "sender_id" : "claude.code@lupin.deepily.ai",
      } ), "lupin" );
    } );

    test( "a hash with no host does not leak into the title", () {
      expect( notificationSenderLabel( <String, dynamic>{
        "sender_id" : "claude.code@#a756441c",
      } ), "Lupin", reason: "there is no project to name, so it falls through" );
    } );
  } );

  group( "notificationSenderLabel — the fallback", () {
    test( "null, empty, and unidentifiable items all get the fallback", () {
      expect( notificationSenderLabel( null ), "Lupin" );
      expect( notificationSenderLabel( <String, dynamic>{} ), "Lupin" );
      expect( notificationSenderLabel(
          <String, dynamic>{ "sender_id": "" } ), "Lupin" );
      expect( notificationSenderLabel(
          <String, dynamic>{ "sender_id": "no-at-sign" } ), "Lupin" );
      expect( notificationSenderLabel(
          <String, dynamic>{ "sender_id": "trailing@" } ), "Lupin" );
    } );

    test( "the label is NEVER empty, for any input", () {
      // The title is the one field read before deciding to look at all; a blank
      // one is worse than a generic one.
      for ( final item in <Map<String, dynamic>?>[
        null,
        <String, dynamic>{},
        <String, dynamic>{ "sender_id": "@" },
        <String, dynamic>{ "sender_id": "a@." },
        <String, dynamic>{ "sender_id": 42 },
        <String, dynamic>{ "voice_persona": null },
      ] ) {
        expect( notificationSenderLabel( item ), isNotEmpty, reason: "item was $item" );
      }
    } );

    test( "a caller may name its own fallback", () {
      expect( notificationSenderLabel( null, fallback: "Somebody" ), "Somebody" );
    } );
  } );

  group( "projectOfSenderId", () {
    test( "the project is the first host segment", () {
      expect( projectOfSenderId(
          "claude.code@lupin-mobile.deepily.ai#a1b2c3d4" ), "lupin-mobile" );
      expect( projectOfSenderId(
          "claude.code@lupin.deepily.ai#a1b2c3d4" ), "lupin" );
    } );

    test( "an address with several @ takes the LAST one as the separator", () {
      expect( projectOfSenderId(
          "weird@name@lupin.deepily.ai#a1b2c3d4" ), "lupin" );
    } );

    test( "null for anything with no project in it", () {
      expect( projectOfSenderId( null ), isNull );
      expect( projectOfSenderId( "" ), isNull );
      expect( projectOfSenderId( "claude.code" ), isNull );
      expect( projectOfSenderId( "claude.code@" ), isNull );
      expect( projectOfSenderId( "claude.code@#hash" ), isNull );
      expect( projectOfSenderId( "claude.code@." ), isNull );
    } );
  } );
}
