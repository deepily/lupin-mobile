// Phase 0 — WS dispatch audit regression test (2026-05-06).
//
// Locks the inner-`notification.type` discriminator pivot in
// `NotificationBloc._onExternalUpdate`. Without this test, a future migration
// could silently drop new event types that ride inside the
// `notification_queue_update` envelope.
//
// Sister doc: src/rnd/v0.1.7/2026.05.06-mobile-port-plans/00-phase-0-dispatch-audit.md
//
// Section A (Phase 1, 2026-05-22 notif-client-sync) — adds dispatch tests for
// the three new commons-* WS event types (`commons_broadcast_ack`,
// `commons_question_received`, `commons_activity`) plus the AC-A5 wire-contract
// grounding test that asserts mobile case-label constants exact-match the
// cosa `valid_types` whitelist.
//
// Section B (Phase 2, 2026-05-23 notif-client-sync) — adds dispatch tests for
// the `speakerphone_changed` WS event type and its typed-event counterpart
// `NotificationsSpeakerphoneChanged`, the legacy-name smoke-test guard
// (`conversation_mode_changed` → default branch, AC-B5), raw-payload
// extraction round-trip for diagnostic fields (AC-B6), and the AC-B7
// wire-contract grounding test that scans cosa source for the
// `speakerphone_changed` emit site (cascade-handoff §0.5 commit `e420ec0`)
// and asserts the mobile-extracted payload field names (`on`, `displaced`,
// `displaced_by`) appear in a window around the emit string.
//
// Pattern mirrors the mocktail tests at the bottom of `notification_bloc_test.dart`
// (the `_MockAudioService` / `_MockTtsOrchestrator` block).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:mocktail/mocktail.dart';

import '../_helpers/stub_dio.dart';

class _MockAudioService extends Mock implements NotificationAudioService {}
class _MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

NotificationItem _makeItem( {
  required String       type,
  String                priority = "urgent",
  String                id       = "n-test",
  String                message  = "body",
  String?               title    = "title",
  String?               senderId,
  Map<String, dynamic>  raw      = const {},
} ) {
  return NotificationItem(
    id                     : id,
    message                : message,
    title                  : title,
    type                   : type,
    priority               : priority,
    timestamp              : DateTime( 2026, 5, 6 ),
    played                 : false,
    playCount              : 0,
    responseRequested      : false,
    suppressDing           : false,
    displayQualifierWidget : false,
    senderId               : senderId,
    raw                    : raw,
  );
}

void main() {
  group( "NotificationBloc — inner-type dispatch (Phase 0)", () {
    late StubAdapter             adapter;
    late NotificationRepository  repo;
    late _MockAudioService       audio;
    late _MockTtsOrchestrator    tts;

    setUp( () {
      adapter = StubAdapter();
      repo    = NotificationRepository( makeDio( adapter ) );
      audio   = _MockAudioService();
      tts     = _MockTtsOrchestrator();
      when( () => audio.handleIncoming(
        priority     : any( named: "priority" ),
        message      : any( named: "message" ),
        title        : any( named: "title" ),
        suppressDing : any( named: "suppressDing" ),
      ) ).thenAnswer( ( _ ) async {} );
      when( () => tts.enqueueIfSpeakable(
        priority : any( named: "priority" ),
        message  : any( named: "message" ),
        title    : any( named: "title" ),
      ) ).thenReturn( null );
    } );

    test(
      "type='voice_persona_assigned' (future feature event) hits default branch — "
      "no audio, no TTS, no crash",
      () async {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts );

        bloc.add( NotificationsExternalUpdate(
          notification: _makeItem( type: "voice_persona_assigned" ),
        ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        verifyNever( () => audio.handleIncoming(
          priority     : any( named: "priority" ),
          message      : any( named: "message" ),
          title        : any( named: "title" ),
          suppressDing : any( named: "suppressDing" ),
        ) );
        verifyNever( () => tts.enqueueIfSpeakable(
          priority : any( named: "priority" ),
          message  : any( named: "message" ),
          title    : any( named: "title" ),
        ) );

        await bloc.close();
      },
    );

    test(
      "type='some_unknown_type' (graceful-degradation safety net) hits default branch — "
      "no audio, no TTS, no crash",
      () async {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts );

        bloc.add( NotificationsExternalUpdate(
          notification: _makeItem( type: "some_unknown_type" ),
        ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        verifyNever( () => audio.handleIncoming(
          priority     : any( named: "priority" ),
          message      : any( named: "message" ),
          title        : any( named: "title" ),
          suppressDing : any( named: "suppressDing" ),
        ) );
        verifyNever( () => tts.enqueueIfSpeakable(
          priority : any( named: "priority" ),
          message  : any( named: "message" ),
          title    : any( named: "title" ),
        ) );

        await bloc.close();
      },
    );

    test(
      "type='alert' (whitelisted existing type) regresses to existing path — "
      "audio AND TTS called",
      () async {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts );

        bloc.add( NotificationsExternalUpdate(
          notification: _makeItem(
            type     : "alert",
            priority : "urgent",
            message  : "Prod is down.",
            title    : "CRIT",
          ),
        ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        verify( () => audio.handleIncoming(
          priority     : "urgent",
          message      : "Prod is down.",
          title        : "CRIT",
          suppressDing : false,
        ) ).called( 1 );
        verify( () => tts.enqueueIfSpeakable(
          priority : "urgent",
          message  : "Prod is down.",
          title    : "CRIT",
        ) ).called( 1 );

        await bloc.close();
      },
    );
  } );

  // ─────────────────────────────────────────────────────────────────────────
  // Section A (Phase 1, 2026-05-22 notif-client-sync) — new commons-* no-op
  // stubs. Each test verifies AC-A2 (`_personasBySender` unchanged via
  // `@visibleForTesting` getter), AC-A3 (no audio/TTS dispatch), and AC-A4
  // (no "Unknown notification.type" log line — captured via `runZoned`
  // + `ZoneSpecification.print`). AC-A1 (fixed-prefix comment form) is a
  // grep-checkable property of the production source and is not blocTested.
  // ─────────────────────────────────────────────────────────────────────────

  group( "NotificationBloc — Section A commons-* no-op stubs", () {
    late StubAdapter             adapter;
    late NotificationRepository  repo;
    late _MockAudioService       audio;
    late _MockTtsOrchestrator    tts;

    setUp( () {
      adapter = StubAdapter();
      repo    = NotificationRepository( makeDio( adapter ) );
      audio   = _MockAudioService();
      tts     = _MockTtsOrchestrator();
      when( () => audio.handleIncoming(
        priority     : any( named: "priority" ),
        message      : any( named: "message" ),
        title        : any( named: "title" ),
        suppressDing : any( named: "suppressDing" ),
      ) ).thenAnswer( ( _ ) async {} );
      when( () => tts.enqueueIfSpeakable(
        priority : any( named: "priority" ),
        message  : any( named: "message" ),
        title    : any( named: "title" ),
      ) ).thenReturn( null );
    } );

    /// Drives the no-op-stub scenario for a single new commons-* event type
    /// and asserts AC-A2 + AC-A3 + AC-A4 in one pass. The `runZoned`
    /// `ZoneSpecification.print` capture is the AC-A4 mechanism (per
    /// F-Krishna-A2): we assert the production `print(...)` in the `default:`
    /// branch DOES NOT fire for the new types.
    Future<void> _exerciseStubCase( String typeString ) async {
      final logs = <String>[];

      await runZoned( () async {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts );

        // AC-A2 — snapshot persona map BEFORE dispatch.
        final before = Map<String, VoicePersona>.from(
          bloc.personasBySenderForTesting,
        );

        bloc.add( NotificationsExternalUpdate(
          notification: _makeItem( type: typeString ),
        ) );
        await Future.delayed( const Duration( milliseconds: 50 ) );

        // AC-A2 — persona map unchanged after dispatch.
        expect(
          bloc.personasBySenderForTesting,
          equals( before ),
          reason: "$typeString must not mutate _personasBySender",
        );

        await bloc.close();
      }, zoneSpecification: ZoneSpecification(
        print: ( self, parent, zone, line ) => logs.add( line ),
      ) );

      // AC-A3 — no audio dispatch, no TTS dispatch.
      verifyNever( () => audio.handleIncoming(
        priority     : any( named: "priority" ),
        message      : any( named: "message" ),
        title        : any( named: "title" ),
        suppressDing : any( named: "suppressDing" ),
      ) );
      verifyNever( () => tts.enqueueIfSpeakable(
        priority : any( named: "priority" ),
        message  : any( named: "message" ),
        title    : any( named: "title" ),
      ) );

      // AC-A4 — no "Unknown notification.type" log emitted (the new cases
      // are documented no-ops, NOT default-branch silent drops).
      expect(
        logs.where( ( l ) => l.contains( "Unknown notification.type" ) ),
        isEmpty,
        reason: "$typeString must not fall through to the default-branch log",
      );
    }

    test(
      "type='commons_broadcast_ack' (Section A no-op stub) — "
      "no audio, no TTS, persona map unchanged, no unknown-type log",
      () => _exerciseStubCase( kNotifTypeCommonsBroadcastAck ),
    );

    test(
      "type='commons_question_received' (Section A no-op stub) — "
      "no audio, no TTS, persona map unchanged, no unknown-type log",
      () => _exerciseStubCase( kNotifTypeCommonsQuestionReceived ),
    );

    test(
      "type='commons_activity' (Section A no-op stub) — "
      "no audio, no TTS, persona map unchanged, no unknown-type log",
      () => _exerciseStubCase( kNotifTypeCommonsActivity ),
    );
  } );

  // ─────────────────────────────────────────────────────────────────────────
  // AC-A5 — Wire-contract grounding. Asserts each Section-A case-label
  // constant exact-matches an entry in the cosa `valid_types` whitelist at
  // sibling `../cosa/rest/routers/notifications.py`. READ-ONLY traversal —
  // the test never invokes git or any cosa-side mutation (cluster-family
  // Sam Stage-3 boundary).
  //
  // Per the cascade Stage-2 F-Krishna-A1 finding + Manager cluster-family
  // doctrine: a fully-green dispatch test does NOT prove the real server
  // contract holds if the case-labels were hand-authored. This test grounds
  // the labels against the cosa source-of-truth at every run.
  // ─────────────────────────────────────────────────────────────────────────

  group( "NotificationBloc — Section A wire-contract grounding (AC-A5)", () {
    test(
      "mobile commons-* case-label constants exact-match cosa valid_types whitelist",
      () async {
        // Resolve cosa whitelist path relative to the lupin-mobile repo root
        // (which is `Directory.current` under `flutter test`).
        const cosaRelPath = "../cosa/rest/routers/notifications.py";
        final file = File( cosaRelPath );

        expect(
          file.existsSync(),
          isTrue,
          reason:
              "AC-A5 wire-contract grounding requires sibling cosa whitelist at "
              "$cosaRelPath. If this fails locally, you are running tests "
              "outside the expected repo layout (lupin/src/lupin-mobile + "
              "lupin/src/cosa siblings). READ-ONLY — no git operations.",
        );

        final source = await file.readAsString();

        // Extract the `valid_types = [ ... ]` block (multi-line list literal).
        final match = RegExp(
          r'valid_types\s*=\s*\[(.*?)\]',
          dotAll: true,
        ).firstMatch( source );

        expect(
          match,
          isNotNull,
          reason:
              "AC-A5 — `valid_types = [...]` block not found in cosa "
              "notifications.py; the whitelist may have moved or been "
              "renamed. Provenance comments in notification_bloc.dart and the "
              "cluster-family fix doctrine need updating.",
        );

        final block = match!.group( 1 )!;

        // Each Section-A constant must appear as a quoted string literal in
        // the cosa whitelist. We assert the quoted form to catch substring
        // false-positives.
        for ( final c in <String>[
          kNotifTypeCommonsBroadcastAck,
          kNotifTypeCommonsQuestionReceived,
          kNotifTypeCommonsActivity,
        ] ) {
          expect(
            block.contains( '"$c"' ) || block.contains( "'$c'" ),
            isTrue,
            reason:
                "AC-A5 — mobile constant '$c' missing from cosa valid_types "
                "whitelist. The wire contract has drifted; either the cosa "
                "whitelist was edited or the mobile constant was hand-edited "
                "out of sync with the server contract.",
          );
        }
      },
    );
  } );

  // ─────────────────────────────────────────────────────────────────────────
  // Section B (Phase 2, 2026-05-23 notif-client-sync) — `speakerphone_changed`
  // dispatch via both the typed event (`NotificationsSpeakerphoneChanged`,
  // tests AC-B2/B3/B4) and the raw `_onExternalUpdate` path
  // (AC-B5 legacy-name guard, AC-B6 diagnostic-field round-trip), plus the
  // AC-B7 wire-contract grounding scan of cosa source.
  // ─────────────────────────────────────────────────────────────────────────

  group( "NotificationBloc — Section B production-source structural (AC-B1)", () {
    test(
      "speakerphone_changed case is present in _onExternalUpdate; "
      "conversation_mode_changed is not in the default-branch future-cases list",
      () async {
        final blocFile = File(
          "lib/features/notifications/domain/notification_bloc.dart",
        );

        expect(
          blocFile.existsSync(),
          isTrue,
          reason:
              "AC-B1 needs the bloc source at "
              "lib/features/notifications/domain/notification_bloc.dart "
              "(run tests from the lupin-mobile repo root).",
        );

        final source = await blocFile.readAsString();

        // AC-B1(a) — the speakerphone_changed case label exists in source.
        expect(
          source.contains( 'case "speakerphone_changed":' ),
          isTrue,
          reason:
              "AC-B1(a) — `case \"speakerphone_changed\":` missing from "
              "_onExternalUpdate; Section B implementation incomplete.",
        );

        // AC-B1(b) — `conversation_mode_changed` is NOT in the future-cases
        // parenthetical of the default-branch comment. Grep for the legacy
        // pattern (the future-cases parenthetical containing
        // conversation_mode_changed) and assert NOT FOUND. The legacy name
        // may appear elsewhere in the file (e.g., in an explanatory note),
        // but it must not be in the future-cases list.
        final futureCasesPattern = RegExp(
          r'this default branch \([^)]*conversation_mode_changed',
          dotAll: true,
        );
        expect(
          futureCasesPattern.hasMatch( source ),
          isFalse,
          reason:
              "AC-B1(b) — `conversation_mode_changed` still listed in the "
              "default-branch 'future cases' parenthetical. Per Q2 the legacy "
              "name is superseded by speakerphone_changed and should not be "
              "documented as a future case.",
        );
      },
    );
  } );

  group(
    "NotificationBloc — Section B speakerphone state via typed event "
    "(AC-B2/B3/B4)",
    () {
      late StubAdapter             adapter;
      late NotificationRepository  repo;
      late _MockAudioService       audio;
      late _MockTtsOrchestrator    tts;

      setUp( () {
        adapter = StubAdapter();
        repo    = NotificationRepository( makeDio( adapter ) );
        audio   = _MockAudioService();
        tts     = _MockTtsOrchestrator();
        when( () => audio.handleIncoming(
          priority     : any( named: "priority" ),
          message      : any( named: "message" ),
          title        : any( named: "title" ),
          suppressDing : any( named: "suppressDing" ),
        ) ).thenAnswer( ( _ ) async {} );
        when( () => tts.enqueueIfSpeakable(
          priority : any( named: "priority" ),
          message  : any( named: "message" ),
          title    : any( named: "title" ),
        ) ).thenReturn( null );
      } );

      test(
        "AC-B2 — NotificationsSpeakerphoneChanged(on: true) stores "
        "SpeakerphoneRecord(on: true) at [senderId]",
        () async {
          final bloc = NotificationBloc( repo, audio: audio, tts: tts );

          bloc.add( const NotificationsSpeakerphoneChanged(
            senderId : "s1",
            on       : true,
          ) );
          await Future.delayed( const Duration( milliseconds: 50 ) );

          expect(
            bloc.speakerphoneBySessionForTesting[ "s1" ],
            equals( const SpeakerphoneRecord( on: true ) ),
            reason:
                "AC-B2 — typed-event on:true must store "
                "SpeakerphoneRecord(on: true) at _speakerphoneBySession[\"s1\"]; "
                "observed via the @visibleForTesting getter.",
          );

          await bloc.close();
        },
      );

      test(
        "AC-B3 — idempotency: same typed event injected twice leaves "
        "SpeakerphoneRecord equal (Equatable contract)",
        () async {
          final bloc = NotificationBloc( repo, audio: audio, tts: tts );

          bloc.add( const NotificationsSpeakerphoneChanged(
            senderId : "s1",
            on       : true,
          ) );
          await Future.delayed( const Duration( milliseconds: 50 ) );
          final first = bloc.speakerphoneBySessionForTesting[ "s1" ];

          bloc.add( const NotificationsSpeakerphoneChanged(
            senderId : "s1",
            on       : true,
          ) );
          await Future.delayed( const Duration( milliseconds: 50 ) );
          final second = bloc.speakerphoneBySessionForTesting[ "s1" ];

          expect(
            first,
            equals( second ),
            reason:
                "AC-B3 — same payload injected twice must leave the record "
                "equal; SpeakerphoneRecord uses Equatable for value-equality.",
          );

          await bloc.close();
        },
      );

      test(
        "AC-B4 — on: false after on: true records SpeakerphoneRecord(on: false)",
        () async {
          final bloc = NotificationBloc( repo, audio: audio, tts: tts );

          bloc.add( const NotificationsSpeakerphoneChanged(
            senderId : "s1",
            on       : true,
          ) );
          await Future.delayed( const Duration( milliseconds: 50 ) );

          bloc.add( const NotificationsSpeakerphoneChanged(
            senderId : "s1",
            on       : false,
          ) );
          await Future.delayed( const Duration( milliseconds: 50 ) );

          expect(
            bloc.speakerphoneBySessionForTesting[ "s1" ],
            equals( const SpeakerphoneRecord( on: false ) ),
            reason:
                "AC-B4 — on:false after on:true must record "
                "SpeakerphoneRecord(on: false); state transitions are "
                "captured per-session.",
          );

          await bloc.close();
        },
      );
    },
  );

  group(
    "NotificationBloc — Section B raw dispatch (AC-B5/B6)",
    () {
      late StubAdapter             adapter;
      late NotificationRepository  repo;
      late _MockAudioService       audio;
      late _MockTtsOrchestrator    tts;

      setUp( () {
        adapter = StubAdapter();
        repo    = NotificationRepository( makeDio( adapter ) );
        audio   = _MockAudioService();
        tts     = _MockTtsOrchestrator();
        when( () => audio.handleIncoming(
          priority     : any( named: "priority" ),
          message      : any( named: "message" ),
          title        : any( named: "title" ),
          suppressDing : any( named: "suppressDing" ),
        ) ).thenAnswer( ( _ ) async {} );
        when( () => tts.enqueueIfSpeakable(
          priority : any( named: "priority" ),
          message  : any( named: "message" ),
          title    : any( named: "title" ),
        ) ).thenReturn( null );
      } );

      test(
        "AC-B5 — raw conversation_mode_changed (legacy name) falls to default "
        "branch; _speakerphoneBySession unchanged (Q2 new-name-only adoption)",
        () async {
          final bloc = NotificationBloc( repo, audio: audio, tts: tts );
          final before = Map<String, SpeakerphoneRecord>.from(
            bloc.speakerphoneBySessionForTesting,
          );

          bloc.add( NotificationsExternalUpdate(
            notification: _makeItem(
              type     : "conversation_mode_changed",
              senderId : "s-legacy",
              raw      : const { "on": true, "displaced": "x", "displaced_by": "y" },
            ),
          ) );
          await Future.delayed( const Duration( milliseconds: 50 ) );

          expect(
            bloc.speakerphoneBySessionForTesting,
            equals( before ),
            reason:
                "AC-B5 — legacy conversation_mode_changed must fall to the "
                "default branch with no _speakerphoneBySession mutation "
                "(mobile is new-name-only per Q2; server's Path III bridge "
                "handles non-mobile clients).",
          );

          await bloc.close();
        },
      );

      test(
        "AC-B6 — raw speakerphone_changed with full payload stores "
        "SpeakerphoneRecord carrying on / displaced / displacedBy verbatim",
        () async {
          final bloc = NotificationBloc( repo, audio: audio, tts: tts );

          bloc.add( NotificationsExternalUpdate(
            notification: _makeItem(
              type     : "speakerphone_changed",
              senderId : "s-sphkr",
              raw      : const {
                "type"         : "speakerphone_changed",
                "on"           : true,
                "displaced"    : "alice@x.y",
                "displaced_by" : "bob@x.y",
              },
            ),
          ) );
          await Future.delayed( const Duration( milliseconds: 50 ) );

          expect(
            bloc.speakerphoneBySessionForTesting[ "s-sphkr" ],
            equals( const SpeakerphoneRecord(
              on          : true,
              displaced   : "alice@x.y",
              displacedBy : "bob@x.y",
            ) ),
            reason:
                "AC-B6 — raw speakerphone_changed payload must round-trip "
                "into a SpeakerphoneRecord with all three diagnostic fields "
                "populated verbatim from n.raw[...] (OSQ B-1 access path).",
          );

          await bloc.close();
        },
      );
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // AC-B7 — Wire-contract grounding for the `speakerphone_changed` payload
  // field names. Scans `../cosa/` recursively for Python files containing
  // the literal "speakerphone_changed" — that's the emit site introduced
  // by the 2026-05-12 speakerphone refactor (cascade-handoff §0.5 commit
  // `e420ec0`). For each emit-site file, asserts the mobile-extracted
  // payload field names (`on`, `displaced`, `displaced_by`) appear within
  // a ~1000-char window around the type string (Python dict-literal scope).
  //
  // READ-ONLY traversal — the test never invokes git or any cosa-side
  // mutation (cluster-family Sam Stage-3 boundary). Per the cascade Stage-2
  // F-Krishna-B3 finding + Manager consolidated wire-grounding doctrine:
  // a fully-green dispatch test does NOT prove the real server contract
  // holds if the field names were hand-authored. This test grounds the
  // names against the cosa source-of-truth at every run.
  // ─────────────────────────────────────────────────────────────────────────

  group(
    "NotificationBloc — Section B wire-contract grounding (AC-B7)",
    () {
      test(
        "speakerphone_changed payload field names exact-match the cosa emit site "
        "(commit e420ec0)",
        () async {
          const cosaDir = "../cosa";
          final dir = Directory( cosaDir );

          expect(
            dir.existsSync(),
            isTrue,
            reason:
                "AC-B7 wire-contract grounding requires sibling cosa dir at "
                "$cosaDir. If this fails locally, you are running tests "
                "outside the expected repo layout (lupin/src/lupin-mobile + "
                "lupin/src/cosa siblings). READ-ONLY — no git operations.",
          );

          // Collect Python files whose contents contain the literal
          // "speakerphone_changed" string (any single/double quote style).
          final emitFiles = <File>[];
          await for ( final entity in dir.list(
            recursive    : true,
            followLinks  : false,
          ) ) {
            if ( entity is! File || !entity.path.endsWith( ".py" ) ) continue;
            try {
              final content = await entity.readAsString();
              if ( content.contains( '"speakerphone_changed"' ) ||
                   content.contains( "'speakerphone_changed'" ) ) {
                emitFiles.add( entity );
              }
            } catch ( _ ) {
              // Skip files we cannot read (encoding, permissions). The
              // grounding assertion runs only on files we CAN read.
            }
          }

          expect(
            emitFiles,
            isNotEmpty,
            reason:
                "AC-B7 — no cosa Python file contains the literal "
                "'speakerphone_changed' string. The emit site may have moved "
                "or been renamed; the provenance comment in "
                "notification_bloc.dart's speakerphone_changed case needs "
                "updating (was commit e420ec0).",
          );

          // For each emit-site file, the mobile-extracted payload field
          // names must appear in a ~1000-char window around the
          // speakerphone_changed string (Python dict-literal scope).
          // Window-scoping reduces false positives from short field names
          // like "on" appearing elsewhere in the same Python file.
          for ( final file in emitFiles ) {
            final content = await file.readAsString();
            var idx = content.indexOf( '"speakerphone_changed"' );
            if ( idx < 0 ) idx = content.indexOf( "'speakerphone_changed'" );
            expect( idx >= 0, isTrue );

            final start  = ( idx - 1000 ).clamp( 0, content.length );
            final end    = ( idx + 1000 ).clamp( 0, content.length );
            final window = content.substring( start, end );

            for ( final name in <String>[ "on", "displaced", "displaced_by" ] ) {
              expect(
                window.contains( '"$name"' ) || window.contains( "'$name'" ),
                isTrue,
                reason:
                    "AC-B7 — payload field name '$name' missing from cosa "
                    "emit-site window in ${file.path}. The wire contract "
                    "has drifted; either the cosa emit was edited or the "
                    "mobile extraction was hand-edited out of sync with "
                    "the server contract.",
              );
            }
          }
        },
      );
    },
  );
}
