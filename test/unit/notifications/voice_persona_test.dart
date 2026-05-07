// Phase 1 — Voice/persona data-model tests.
//
// Asserts:
//   - liberal fromJson round-trip (Q7)
//   - null-defense contract (F1) — missing/malformed fields → null, no throw
//   - equality keyed on voiceId (Phase 1.2 / Q3 contract)
//
// Fixture file at test/fixtures/notifications/voice-persona-adam.json shadows
// the canonical server-bridge shape. Inline fixtures here keep the unit test
// hermetic; the fixture file is consumed by the service-integration leg.

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/voice_persona.dart';

void main() {
  group( "VoicePersona.fromJson", () {
    test( "round-trips canonical Adam persona (borrowed=false)", () {
      final src = {
        "name"         : "Adam",
        "voice_id"     : "pNInz6obpgDQGcFmaJgB",
        "icon"         : "🌑",
        "color"        : "#3F51B5",
        "borrowed"     : false,
        "assigned_at"  : "2026-04-28T20:33:42.000Z",
        "display_name" : "Adam",
      };

      final p = VoicePersona.fromJson( src );

      expect( p.name,                  "Adam" );
      expect( p.voiceId,                "pNInz6obpgDQGcFmaJgB" );
      expect( p.icon,                   "🌑" );
      expect( p.color,                  "#3F51B5" );
      expect( p.borrowed,               isFalse );
      expect( p.assignedAt!.year,       2026 );
      expect( p.assignedAt!.month,      4 );
      expect( p.assignedAt!.day,        28 );
      expect( p.assignedAt!.isUtc,      isTrue );
      expect( p.displayName,            "Adam" );
    } );

    test( "preserves borrowed=true variant", () {
      final p = VoicePersona.fromJson( {
        "name"     : "Bella",
        "voice_id" : "EXAVITQu4vr4xnSDxMaL",
        "borrowed" : true,
      } );

      expect( p.borrowed,  isTrue );
      expect( p.voiceId,   "EXAVITQu4vr4xnSDxMaL" );
    } );

    test( "null-defense: missing fields default to null, never throws", () {
      // Empty object — every field absent. Per F1 null-defense contract.
      final p = VoicePersona.fromJson( {} );

      expect( p.name,        isNull );
      expect( p.voiceId,     isNull );
      expect( p.icon,        isNull );
      expect( p.color,       isNull );
      expect( p.borrowed,    isFalse ); // default per Q7
      expect( p.assignedAt,  isNull );
      expect( p.displayName, isNull );
    } );

    test( "null-defense: malformed types coerce to null without throwing", () {
      // Server returning surprising shapes — numeric voice_id, bool icon, etc.
      // The liberal parser must NOT throw; it just nulls the bad fields.
      final p = VoicePersona.fromJson( {
        "name"        : 42,           // wrong type
        "voice_id"    : true,         // wrong type
        "icon"        : null,
        "color"       : "#FF0000",    // valid
        "borrowed"    : "yes",        // wrong type — the `== true` test rejects
        "assigned_at" : "not-a-date", // unparseable
        "display_name": ["array"],    // wrong type
      } );

      expect( p.name,        isNull );  // 42 is not a String
      expect( p.voiceId,     isNull );  // true is not a String
      expect( p.icon,        isNull );
      expect( p.color,       "#FF0000" );
      expect( p.borrowed,    isFalse ); // "yes" != true
      expect( p.assignedAt,  isNull );  // tryParse returned null
      expect( p.displayName, isNull );
    } );

    test( "forward-compatibility: unknown fields are ignored, not thrown on", () {
      // Server may grow new fields per Q7. Liberal parser ignores them.
      final p = VoicePersona.fromJson( {
        "name"             : "Sam",
        "voice_id"         : "yoZ06aMxZJJ28mfd3POQ",
        "borrowed"         : false,
        "future_field_v2"  : { "complex": "shape" },
        "another_addition" : 99,
      } );

      expect( p.name,    "Sam" );
      expect( p.voiceId, "yoZ06aMxZJJ28mfd3POQ" );
    } );
  } );

  group( "VoicePersona equality (keyed on voiceId)", () {
    test( "same voiceId compares equal even with different other fields", () {
      const a = VoicePersona( name: "Adam", voiceId: "v-1", color: "#AAA" );
      const b = VoicePersona( name: "Bobby", voiceId: "v-1", color: "#BBB", borrowed: true );

      expect( a == b,             isTrue );
      expect( a.hashCode == b.hashCode, isTrue );
    } );

    test( "different voiceId compares not equal", () {
      const a = VoicePersona( name: "Adam", voiceId: "v-1" );
      const b = VoicePersona( name: "Adam", voiceId: "v-2" );

      expect( a == b, isFalse );
    } );

    test( "null voiceId compares equal to null voiceId", () {
      // Two persona-less placeholders compare equal. Documented edge case;
      // avoids surprising != for "no persona" twins. Bloc state map keys on
      // senderId, not on persona, so this collision is benign.
      const a = VoicePersona( name: "X" );
      const b = VoicePersona( name: "Y" );

      expect( a == b, isTrue );
    } );
  } );

  group( "VoicePersona.toJson", () {
    test( "round-trip preserves all fields", () {
      final src = VoicePersona(
        name        : "Adam",
        voiceId     : "pNInz6obpgDQGcFmaJgB",
        icon        : "🌑",
        color       : "#3F51B5",
        borrowed    : false,
        assignedAt  : DateTime.utc( 2026, 4, 28, 20, 33, 42 ),
        displayName : "Adam",
      );

      final round = VoicePersona.fromJson( src.toJson() );

      expect( round, src );  // equality (voiceId match)
      expect( round.name,        src.name );
      expect( round.color,       src.color );
      expect( round.borrowed,    src.borrowed );
      expect( round.assignedAt,  src.assignedAt );
      expect( round.displayName, src.displayName );
    } );
  } );
}
