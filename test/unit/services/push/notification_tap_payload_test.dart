import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/push/notification_tap_payload.dart';

/// Row d9bc6f6c — the tap payload codec.
///
/// 🔴 WHY THE TOLERANCE TESTS ARE THE POINT OF THIS FILE, not padding around the
/// round-trip. The string under test is written by a background isolate and read
/// back by a different process, from an Android intent, after an arbitrary delay
/// that can include an app upgrade. Every one of those steps can hand [decode] a
/// string this build never wrote. `decode` is on the COLD-START path — `main()`
/// calls it before `runApp` — so a throw there is not a missed feature, it is an
/// app that will not open from a notification at all, which is strictly worse
/// than the bug being fixed.
void main() {
  group( "NotificationTapPayload — round trip", () {
    test( "an encoded payload decodes back to an equal value", () {
      const original = NotificationTapPayload(
        notificationId : "n-4821",
        senderId       : "claude.code@lupin.deepily.ai#a1b2c3d4",
      );

      final decoded = NotificationTapPayload.decode( original.encode() );

      expect( decoded, original );
      expect( decoded!.notificationId, "n-4821" );
      expect( decoded.senderId, "claude.code@lupin.deepily.ai#a1b2c3d4" );
      expect( decoded.isRoutable, isTrue );
    } );

    test( "the encoded form is JSON with the server's own field names", () {
      // The wire names match the server's notification object (`id` becomes
      // `notification_id` to say WHICH id it is; `sender_id` is verbatim). A
      // reader of the stored payload in `adb shell dumpsys notification` should
      // recognise the fields without this file open.
      final map = jsonDecode( const NotificationTapPayload(
        notificationId : "n-1", senderId: "who#1" ).encode() ) as Map;

      expect( map[ "notification_id" ], "n-1" );
      expect( map[ "sender_id" ], "who#1" );
    } );

    test( "a sender-less payload round-trips, and reports itself unroutable", () {
      const fallback = NotificationTapPayload( notificationId: "n-9" );

      final decoded = NotificationTapPayload.decode( fallback.encode() );

      expect( decoded, fallback );
      expect( decoded!.senderId, isNull );
      expect( decoded.isRoutable, isFalse,
          reason: "a `ws_wake` fallback notification has no conversation to open; "
                  "the tap must degrade to a plain launch, not to a selection of "
                  "some arbitrary sender" );
    } );
  } );

  group( "NotificationTapPayload.decode — total over hostile input", () {
    // Each of these is a string the plugin could genuinely hand back. `''` is
    // the plugin's OWN default: `show()` sends `'payload': payload ?? ''`, so
    // every notification this app posted before this row carries exactly that.
    const hostile = <String, String?>{
      "null"                   : null,
      "the plugin's default"   : "",
      "whitespace"             : "   ",
      "not JSON at all"        : "n-4821",
      "truncated JSON"         : '{"notification_id":"n-48',
      "a JSON list"            : '["n-4821"]',
      "a bare JSON string"     : '"n-4821"',
      "a JSON number"          : "42",
      "an object, no id"       : '{"sender_id":"who#1"}',
      "an empty id"            : '{"notification_id":"","sender_id":"who#1"}',
      "a whitespace id"        : '{"notification_id":"  ","sender_id":"who#1"}',
      "a null id"              : '{"notification_id":null}',
      "an empty object"        : "{}",
    };

    hostile.forEach( ( label, raw ) {
      test( "$label decodes to null without throwing", () {
        expect( NotificationTapPayload.decode( raw ), isNull );
      } );
    } );

    test( "an id-carrying payload survives unknown extra fields", () {
      // Forward compatibility in the direction that actually happens: a NEWER
      // build writes the payload, an OLDER one is somehow reading it, or this
      // build gains a field later. Unknown keys are ignored, not fatal.
      final decoded = NotificationTapPayload.decode(
        '{"notification_id":"n-7","sender_id":"who#7","future_field":{"a":1}}' );

      expect( decoded?.notificationId, "n-7" );
      expect( decoded?.senderId, "who#7" );
    } );

    test( "a blank sender_id becomes null rather than the empty string", () {
      final decoded = NotificationTapPayload.decode(
        '{"notification_id":"n-7","sender_id":"   "}' );

      expect( decoded, isNotNull );
      expect( decoded!.senderId, isNull,
          reason: '"" is not a sender id, and letting it through would make '
                  'isRoutable true for a tap that can select nothing' );
      expect( decoded.isRoutable, isFalse );
    } );
  } );

  group( "NotificationTapPayload.fromNotification — built from the SHOWN item", () {
    test( "reads id and sender_id off the server's notification object", () {
      // Field names and shape per the captured wire sample,
      // test/fixtures/notifications/notification-with-persona.json.
      final payload = NotificationTapPayload.fromNotification( <String, dynamic>{
        "id"        : "fixture-persona-1",
        "message"   : "Build complete.",
        "title"     : "Adam-session task done",
        "sender_id" : "claude.code@lupin-mobile.deepily.ai#a756441c",
      } );

      expect( payload?.notificationId, "fixture-persona-1" );
      expect( payload?.senderId, "claude.code@lupin-mobile.deepily.ai#a756441c" );
    } );

    test( "an item with no sender_id yields an unroutable payload, not null", () {
      final payload = NotificationTapPayload.fromNotification(
        <String, dynamic>{ "id": "n-3", "message": "hi" } );

      expect( payload, isNotNull,
          reason: "the id is still worth carrying — it is what the handle-once "
                  "dedupe keys on" );
      expect( payload!.isRoutable, isFalse );
    } );

    test( "a null item, or one with no usable id, yields null", () {
      expect( NotificationTapPayload.fromNotification( null ), isNull );
      expect( NotificationTapPayload.fromNotification( <String, dynamic>{} ), isNull );
      expect( NotificationTapPayload.fromNotification(
          <String, dynamic>{ "id": "" } ), isNull );
      expect( NotificationTapPayload.fromNotification(
          <String, dynamic>{ "id": "   " } ), isNull );
    } );

    test( "a non-string id is coerced, because the wire is not typed", () {
      // `id` is a string in every sample, but this map comes off a JSON decode
      // of a server response and nothing in the client enforces that.
      expect(
        NotificationTapPayload.fromNotification(
            <String, dynamic>{ "id": 4821, "sender_id": "who#1" } )?.notificationId,
        "4821" );
    } );
  } );
}
