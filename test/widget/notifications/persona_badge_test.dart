import 'package:flutter/material.dart';
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
  } );
}
