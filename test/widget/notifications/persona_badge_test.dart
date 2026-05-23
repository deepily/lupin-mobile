import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/voice_persona.dart';
import 'package:lupin_mobile/features/notifications/presentation/persona_badge.dart';
import 'package:lupin_mobile/shared/painters/dashed_border_painter.dart';

/// Phase 3 widget tests for `PersonaBadge` per
/// `src/rnd/v0.1.7/2026.05.06-mobile-port-plans/voice-persona/04-testing-validation.md`
/// rows 3.1–3.4 (3.5 lives in `conversation_screen_test.dart`; 3.6 is HUMAN).
void main() {
  group( "PersonaBadge", () {
    const adam = VoicePersona(
      name        : "Adam",
      voiceId     : "pNInz6obpgDQGcFmaJgB",
      icon        : "🌑",
      color       : "#212121",
      borrowed    : false,
      displayName : "Adam (deep)",
    );

    const adamBorrowed = VoicePersona(
      name        : "Adam",
      voiceId     : "pNInz6obpgDQGcFmaJgB",
      icon        : "🌑",
      color       : "#212121",
      borrowed    : true,
      displayName : "Adam (deep)",
    );

    Widget host( Widget child, { ThemeMode themeMode = ThemeMode.light } ) {
      return MaterialApp(
        themeMode : themeMode,
        theme     : ThemeData.light( useMaterial3: true ),
        darkTheme : ThemeData.dark( useMaterial3: true ),
        home      : Scaffold( body: Center( child: child ) ),
      );
    }

    testWidgets( "3.1 — present + colored: badge renders with persona color", ( tester ) async {
      await tester.pumpWidget( host( const PersonaBadge(
        persona  : adam,
        senderId : "s-1",
      ) ) );

      final badge = find.byKey( Key( "${TestKeys.personaBadgePrefix}s-1" ) );
      expect( badge, findsOneWidget );

      final avatar = tester.widget<CircleAvatar>( find.byType( CircleAvatar ) );
      expect( avatar.backgroundColor, const Color( 0xFF212121 ) );

      // Emoji is the avatar child (not letter substitution per the F9 contract).
      expect( find.text( "🌑" ), findsOneWidget );
    } );

    testWidgets( "3.2 — absent: persona == null renders nothing under the badge key", ( tester ) async {
      await tester.pumpWidget( host( const PersonaBadge(
        persona  : null,
        senderId : "s-1",
      ) ) );

      expect( find.byKey( Key( "${TestKeys.personaBadgePrefix}s-1" ) ),     findsNothing );
      expect( find.byKey( Key( "${TestKeys.personaBadgeDashedPrefix}s-1" ) ), findsNothing );
      expect( find.byType( CircleAvatar ), findsNothing );
    } );

    testWidgets( "3.3 — borrowed: dashed border painter overlays the avatar", ( tester ) async {
      await tester.pumpWidget( host( const PersonaBadge(
        persona  : adamBorrowed,
        senderId : "s-2",
      ) ) );

      // Dashed-variant key is used (not the plain prefix).
      expect( find.byKey( Key( "${TestKeys.personaBadgeDashedPrefix}s-2" ) ), findsOneWidget );
      expect( find.byKey( Key( "${TestKeys.personaBadgePrefix}s-2" ) ),       findsNothing );

      // CustomPaint with DashedBorderPainter is in the tree.
      final dashedPaint = find.byWidgetPredicate(
        ( w ) => w is CustomPaint && w.painter is DashedBorderPainter,
      );
      expect( dashedPaint, findsOneWidget );
    } );

    testWidgets( "3.4a — light + dark mode both render with persona color background", ( tester ) async {
      await tester.pumpWidget( host(
        const PersonaBadge( persona: adam, senderId: "s-1" ),
        themeMode: ThemeMode.light,
      ) );
      var avatar = tester.widget<CircleAvatar>( find.byType( CircleAvatar ) );
      expect( avatar.backgroundColor, const Color( 0xFF212121 ) );

      await tester.pumpWidget( host(
        const PersonaBadge( persona: adam, senderId: "s-1" ),
        themeMode: ThemeMode.dark,
      ) );
      avatar = tester.widget<CircleAvatar>( find.byType( CircleAvatar ) );
      expect( avatar.backgroundColor, const Color( 0xFF212121 ) );
    } );

    testWidgets( "3.4b — broken-emoji codepoint resilience: no error, badge still renders with color", ( tester ) async {
      const broken = VoicePersona(
        name        : "Glitch",
        voiceId     : "vx-broken",
        icon        : "\u{1FAFF}", // intentionally broken/unassigned-feeling codepoint
        color       : "#FFD600",
        borrowed    : false,
        displayName : "Glitch (test)",
      );

      await tester.pumpWidget( host( const PersonaBadge(
        persona  : broken,
        senderId : "s-glitch",
      ) ) );

      // No exceptions thrown during build (tester would have surfaced them).
      expect( tester.takeException(), isNull );

      // Badge present with persona color background — primary disambiguator
      // survives even if the glyph fails to render.
      final badge = find.byKey( Key( "${TestKeys.personaBadgePrefix}s-glitch" ) );
      expect( badge, findsOneWidget );

      final avatar = tester.widget<CircleAvatar>( find.byType( CircleAvatar ) );
      expect( avatar.backgroundColor, const Color( 0xFFFFD600 ) );
    } );

    testWidgets( "malformed color string falls back to theme primary (failure-mode contract)", ( tester ) async {
      const oddColor = VoicePersona(
        name     : "OddColor",
        voiceId  : "vx-odd",
        icon     : "🪨",
        color    : "not-a-hex",
        borrowed : false,
      );

      await tester.pumpWidget( host( const PersonaBadge(
        persona  : oddColor,
        senderId : "s-odd",
      ) ) );

      expect( tester.takeException(), isNull );
      final badge = find.byKey( Key( "${TestKeys.personaBadgePrefix}s-odd" ) );
      expect( badge, findsOneWidget );
    } );

    // ─────────────────────────────────────────────────────────────────────
    // Section C (Phase 3, 2026-05-23 notif-client-sync) — overflow variant.
    // Per cascade Stage-2 F-Krishna-C1 + ratified §Implementation handoff:
    // `VoicePersona.overflow=true` renders a dotted border via
    // `DashedBorderPainter` extended with `cap: StrokeCap.round` + short
    // `dashLength` (≈ strokeWidth), plus a `✱` glyph overlay. Overflow takes
    // precedence over borrowed (web composition rule). The ✱ glyph (AC-C2)
    // is the load-bearing disambiguator; perceptual dotted-vs-dashed
    // distinctness at 40/24px is AC-C5 (EXECUTOR: HUMAN on-device VP,
    // deferred per `feedback_dev_server_laptop_split`).
    // ─────────────────────────────────────────────────────────────────────

    group( "Section C — overflow variant", () {
      const adamOverflow = VoicePersona(
        name        : "Adam",
        voiceId     : "pNInz6obpgDQGcFmaJgB",
        icon        : "🌑",
        color       : "#212121",
        borrowed    : false,
        overflow    : true,
        displayName : "Adam (overflow)",
      );

      const adamBoth = VoicePersona(
        name        : "Adam",
        voiceId     : "pNInz6obpgDQGcFmaJgB",
        icon        : "🌑",
        color       : "#212121",
        borrowed    : true,
        overflow    : true,
        displayName : "Adam (overflow + borrowed; overflow precedence)",
      );

      DashedBorderPainter findPainter( WidgetTester tester ) {
        final paintWidget = tester.widget<CustomPaint>(
          find.byWidgetPredicate(
            ( w ) => w is CustomPaint && w.painter is DashedBorderPainter,
          ),
        );
        return paintWidget.painter as DashedBorderPainter;
      }

      testWidgets(
        "AC-C1(T,F) — overflow only: dotted painter (cap: StrokeCap.round) is invoked",
        ( tester ) async {
          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adamOverflow,
            senderId : "s-of",
          ) ) );
          expect( tester.takeException(), isNull );

          expect( find.byKey( Key( "${TestKeys.personaBadgeDottedPrefix}s-of" ) ), findsOneWidget );
          expect( find.byKey( Key( "${TestKeys.personaBadgePrefix}s-of"       ) ), findsNothing );
          expect( find.byKey( Key( "${TestKeys.personaBadgeDashedPrefix}s-of" ) ), findsNothing );

          expect(
            findPainter( tester ).cap,
            StrokeCap.round,
            reason: "AC-C1(T,F) — overflow uses dotted (cap: StrokeCap.round) configuration.",
          );
        },
      );

      testWidgets(
        "AC-C1(T,T) — overflow + borrowed: overflow precedence — dotted painter (cap: round)",
        ( tester ) async {
          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adamBoth,
            senderId : "s-both",
          ) ) );
          expect( tester.takeException(), isNull );

          // Dotted-variant key wins precedence over dashed (web composition rule).
          expect( find.byKey( Key( "${TestKeys.personaBadgeDottedPrefix}s-both" ) ), findsOneWidget );
          expect( find.byKey( Key( "${TestKeys.personaBadgeDashedPrefix}s-both" ) ), findsNothing );

          expect(
            findPainter( tester ).cap,
            StrokeCap.round,
            reason:
                "AC-C1(T,T) — overflow takes precedence over borrowed; "
                "render is dotted, NOT dashed.",
          );
        },
      );

      testWidgets(
        "AC-C1(F,T) — borrowed only: dashed painter (cap: StrokeCap.butt) — "
        "existing behavior unchanged",
        ( tester ) async {
          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adamBorrowed,
            senderId : "s-bor",
          ) ) );
          expect( tester.takeException(), isNull );

          expect(
            findPainter( tester ).cap,
            StrokeCap.butt,
            reason:
                "AC-C1(F,T) — borrowed-only is dashed (cap: StrokeCap.butt); "
                "unchanged from existing behavior pre-Section-C.",
          );
        },
      );

      testWidgets(
        "AC-C1(F,F) — neither: plain badge, no painter overlay",
        ( tester ) async {
          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adam,
            senderId : "s-pl",
          ) ) );
          expect( tester.takeException(), isNull );

          expect( find.byKey( Key( "${TestKeys.personaBadgePrefix}s-pl"       ) ), findsOneWidget );
          expect( find.byKey( Key( "${TestKeys.personaBadgeDottedPrefix}s-pl" ) ), findsNothing );
          expect( find.byKey( Key( "${TestKeys.personaBadgeDashedPrefix}s-pl" ) ), findsNothing );

          expect(
            find.byWidgetPredicate(
              ( w ) => w is CustomPaint && w.painter is DashedBorderPainter,
            ),
            findsNothing,
            reason: "AC-C1(F,F) — neither variant: no DashedBorderPainter overlay.",
          );
        },
      );

      testWidgets(
        "AC-C2 — ✱ glyph present for overflow=true only (load-bearing disambiguator)",
        ( tester ) async {
          // overflow=true variants — ✱ MUST appear.
          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adamOverflow,
            senderId : "s-of",
          ) ) );
          expect( find.text( "✱" ), findsOneWidget,
            reason: "AC-C2 — ✱ glyph must appear for overflow=true, borrowed=false." );

          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adamBoth,
            senderId : "s-both",
          ) ) );
          expect( find.text( "✱" ), findsOneWidget,
            reason: "AC-C2 — ✱ glyph must appear for overflow=true, borrowed=true (precedence case)." );

          // overflow=false variants — ✱ MUST NOT appear.
          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adam,
            senderId : "s-pl",
          ) ) );
          expect( find.text( "✱" ), findsNothing,
            reason: "AC-C2 — ✱ glyph must NOT appear for plain (overflow=false, borrowed=false)." );

          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adamBorrowed,
            senderId : "s-bor",
          ) ) );
          expect( find.text( "✱" ), findsNothing,
            reason: "AC-C2 — ✱ glyph must NOT appear for borrowed-only (overflow=false, borrowed=true)." );
        },
      );

      testWidgets(
        "AC-C3 — overflow badge discoverable via personaBadgeDottedPrefix-keyed finder",
        ( tester ) async {
          await tester.pumpWidget( host( const PersonaBadge(
            persona  : adamOverflow,
            senderId : "s-of",
          ) ) );
          expect(
            find.byKey( Key( "${TestKeys.personaBadgeDottedPrefix}s-of" ) ),
            findsOneWidget,
            reason:
                "AC-C3 — overflow variant must be discoverable via "
                "personaBadgeDottedPrefix-keyed finder for test ergonomics "
                "(mirrors the personaBadgeDashedPrefix pattern for borrowed).",
          );
        },
      );

      testWidgets(
        "AC-C4 — dotted configuration renders a pixel-distinct paint path from "
        "dashed (direct two-render diff, NOT a Flutter golden-file)",
        ( tester ) async {
          // Direct two-render pixel-diff via RenderRepaintBoundary.toImage —
          // NOT a Flutter golden-file comparison (no committed baseline).
          // Per cascade Stage-2 F-Krishna-C1(ii): golden semantics are
          // reserved for baseline-compare; this is a render-A ≠ render-B
          // assertion that proves the two configurations differ structurally
          // at pixel level.

          await tester.pumpWidget( host(
            const RepaintBoundary( child: PersonaBadge(
              persona  : adamOverflow,
              senderId : "s-of",
            ) ),
          ) );
          await tester.pumpAndSettle();
          final overflowBoundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType( RepaintBoundary ),
          );
          final overflowImg   = await overflowBoundary.toImage( pixelRatio: 1.0 );
          final overflowBytes = await overflowImg.toByteData(
            format: ui.ImageByteFormat.png,
          );

          await tester.pumpWidget( host(
            const RepaintBoundary( child: PersonaBadge(
              persona  : adamBorrowed,
              senderId : "s-bor",
            ) ),
          ) );
          await tester.pumpAndSettle();
          final borrowedBoundary = tester.renderObject<RenderRepaintBoundary>(
            find.byType( RepaintBoundary ),
          );
          final borrowedImg   = await borrowedBoundary.toImage( pixelRatio: 1.0 );
          final borrowedBytes = await borrowedImg.toByteData(
            format: ui.ImageByteFormat.png,
          );

          expect( overflowBytes, isNotNull );
          expect( borrowedBytes, isNotNull );

          expect(
            overflowBytes!.buffer.asUint8List(),
            isNot( equals( borrowedBytes!.buffer.asUint8List() ) ),
            reason:
                "AC-C4 — overflow (dotted + ✱) and borrowed (dashed) renders "
                "must produce different pixel outputs. Direct two-render diff, "
                "NOT a Flutter golden-file comparison.",
          );
        },
      );
    } );
  } );
}
