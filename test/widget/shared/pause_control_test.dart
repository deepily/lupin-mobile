/// The promoted shared speech-hold control — AC-S3.5, AC-S3.5b, AC-S3.5c.
///
/// Behavior is asserted HERE, once. A screen that mounts these widgets
/// asserts only that they are mounted; it does not re-test them, which is
/// the routing AC-S3.5c fixes (an S3 requirement previously discharged
/// inside seat A's screen test).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/shared/widgets/tts_pause_control.dart';

class _MockTts extends Mock implements TtsOrchestrator {}

void main() {
  late _MockTts tts;
  late StreamController<bool> pausedCtrl;
  late StreamController<int>  depthCtrl;

  const toggleKey = Key( 'test.pauseToggle' );
  const bannerKey = Key( 'test.pausedBanner' );

  /// [startPaused] is the whole point of AC-S3.5b: the orchestrator is a
  /// registered singleton, so a control can mount long after the hold was
  /// set on another screen.
  void arrange( { required bool startPaused, int depth = 0 } ) {
    when( () => tts.pausedStream     ).thenAnswer( ( _ ) => pausedCtrl.stream );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => depthCtrl.stream );
    when( () => tts.isPaused         ).thenReturn( startPaused );
    when( () => tts.queueDepth       ).thenReturn( depth );
    when( () => tts.pause()          ).thenReturn( null );
    when( () => tts.resume()         ).thenReturn( null );
  }

  Widget host( Widget child ) => MaterialApp( home: Scaffold( body: child ) );

  setUp( () {
    tts        = _MockTts();
    pausedCtrl = StreamController<bool>.broadcast();
    depthCtrl  = StreamController<int>.broadcast();
  } );

  tearDown( () async {
    await pausedCtrl.close();
    await depthCtrl.close();
  } );

  IconData iconOf( WidgetTester tester ) =>
      ( tester.widget<Icon>( find.descendant(
          of: find.byKey( toggleKey ), matching: find.byType( Icon ) ) ) ).icon!;

  group( 'TtsPauseToggle', () {
    testWidgets( 'AC-S3.5 — renders from pausedStream, not local state: an '
                 'emission flips it with NO tap', ( tester ) async {
      arrange( startPaused: false );
      await tester.pumpWidget( host( TtsPauseToggle( tts: tts, toggleKey: toggleKey ) ) );
      expect( iconOf( tester ), Icons.pause_circle, reason: 'not held yet' );

      pausedCtrl.add( true );
      await tester.pump();

      expect( iconOf( tester ), Icons.play_circle,
              reason: 'the hold was set elsewhere; nobody tapped this control' );
      verifyNever( () => tts.pause() );
    } );

    testWidgets( 'AC-S3.5b — mounted while ALREADY paused, it shows paused',
                 ( tester ) async {
      arrange( startPaused: true );
      await tester.pumpWidget( host( TtsPauseToggle( tts: tts, toggleKey: toggleKey ) ) );

      // No stream emission at all. `pausedStream` DOES replay on subscribe
      // now (row a3fdb6ad, landed) — but the replay arrives a microtask late,
      // and this mock emits nothing whatsoever. So `initialData` is still what
      // paints the first frame, and still what this asserts. Two belts, and
      // dropping either one is a visible regression: without the seed a
      // one-frame flash, without the replay a control that reads wrong until
      // someone toggles.
      expect( iconOf( tester ), Icons.play_circle );
    } );

    testWidgets( 'tapping toggles the orchestrator in the right direction',
                 ( tester ) async {
      arrange( startPaused: false );
      await tester.pumpWidget( host( TtsPauseToggle( tts: tts, toggleKey: toggleKey ) ) );

      await tester.tap( find.byKey( toggleKey ) );
      verify( () => tts.pause() ).called( 1 );

      pausedCtrl.add( true );
      await tester.pump();
      await tester.tap( find.byKey( toggleKey ) );
      verify( () => tts.resume() ).called( 1 );
    } );
  } );

  group( 'TtsPausedBanner', () {
    testWidgets( 'AC-S3.5c — a held queue is EXPLAINED, with the live count',
                 ( tester ) async {
      arrange( startPaused: true, depth: 3 );
      await tester.pumpWidget( host( TtsPausedBanner( tts: tts, bannerKey: bannerKey ) ) );

      expect( find.byKey( bannerKey ), findsOneWidget );
      expect( find.textContaining( 'Speech held' ), findsOneWidget );
      expect( find.textContaining( '3 message(s)' ), findsOneWidget );

      // Held ≠ lost: the count ticks up while the hold stands.
      depthCtrl.add( 5 );
      await tester.pump();
      expect( find.textContaining( '5 message(s)' ), findsOneWidget );
    } );

    testWidgets( 'AC-S3.5b — mounted while ALREADY paused, the banner is there',
                 ( tester ) async {
      arrange( startPaused: true, depth: 1 );
      await tester.pumpWidget( host( TtsPausedBanner( tts: tts, bannerKey: bannerKey ) ) );
      expect( find.byKey( bannerKey ), findsOneWidget,
              reason: 'seeded from isPaused; no emission has occurred' );
    } );

    testWidgets( 'it is absent while speech is flowing', ( tester ) async {
      arrange( startPaused: false );
      await tester.pumpWidget( host( TtsPausedBanner( tts: tts, bannerKey: bannerKey ) ) );
      expect( find.byKey( bannerKey ), findsNothing );
    } );

    testWidgets( 'AC-S3.5c — the optional reason is appended, so a screen can '
                 'say why without inventing a provenance', ( tester ) async {
      arrange( startPaused: true, depth: 2 );
      await tester.pumpWidget( host( TtsPausedBanner(
        tts       : tts,
        bannerKey : bannerKey,
        reason    : 'held from another screen',
      ) ) );
      expect( find.textContaining( 'held from another screen' ), findsOneWidget );
    } );
  } );

  group( 'AC-S3.5c — ONE implementation, not a third copy', () {
    test( 'no other file in lib/ builds its own view over pausedStream', () {
      final offenders = <String>[];
      for ( final f in Directory( 'lib' ).listSync( recursive: true ).whereType<File>() ) {
        if ( !f.path.endsWith( '.dart' ) ) continue;
        // The orchestrator DECLARES the stream; the shared control is the
        // one sanctioned consumer. Anyone else rendering from it is the
        // third StreamBuilder this AC exists to prevent.
        if ( f.path.endsWith( 'services/tts/tts_orchestrator.dart' ) ) continue;
        if ( f.path.endsWith( 'shared/widgets/tts_pause_control.dart' ) ) continue;
        final src = f.readAsStringSync();
        // A doc comment mentioning the stream is not a consumer; a
        // subscription is.
        final consumes = RegExp( r'(stream\s*:\s*[\w.]*\.?pausedStream|'
                                 r'pausedStream\s*\.\s*listen)' ).hasMatch( src );
        if ( consumes ) offenders.add( f.path );
      }
      expect( offenders, isEmpty,
              reason: 'mount TtsPauseToggle / TtsPausedBanner instead of '
                      'rendering pausedStream again' );
    } );
  } );
}
