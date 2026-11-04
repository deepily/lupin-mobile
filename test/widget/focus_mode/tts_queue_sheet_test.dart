import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/tts_queue_sheet.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockTts extends Mock implements TtsOrchestrator {}

/// TtsQueueSheet (Rick 2026-08-21 — web `#tts-queue-section` parity):
/// current row + Skip, pending rows + Delete, Clear queue, Stop all, empty
/// state; every control calls the orchestrator verb it names.
void main() {
  late _MockTts tts;
  late StreamController<List<TtsQueueItem>> ctrl;

  const tiff = TtsSender( senderId: 'cc#1', name: 'Tiffany', icon: '💍' );
  const sys  = TtsSender( senderId: 'pytest.runner@lupin#2' );
  const items = [
    TtsQueueItem( id: 10, priority: 'high', text: 'the current one', sender: tiff, isCurrent: true ),
    TtsQueueItem( id: 11, priority: 'low',  text: 'noisy test line',  sender: sys,  isCurrent: false ),
    TtsQueueItem( id: 12, priority: 'low',  text: 'another queued',   sender: tiff, isCurrent: false ),
  ];

  setUp( () {
    tts  = _MockTts();
    ctrl = StreamController<List<TtsQueueItem>>.broadcast();
    final stream = ctrl.stream;   // one stream instance: StreamBuilder must not resubscribe per build
    when( () => tts.queueStream   ).thenAnswer( ( _ ) => stream );
    when( () => tts.queueSnapshot ).thenReturn( items );
    when( () => tts.skipCurrent() ).thenAnswer( ( _ ) async {} );
    when( () => tts.stopAll()     ).thenAnswer( ( _ ) async {} );
    when( () => tts.removeQueued( any() ) ).thenReturn( true );
    when( () => tts.clearQueued() ).thenReturn( null );
    when( () => tts.lastOutcome   ).thenReturn( null );
    when( () => tts.outcomeStream ).thenAnswer( ( _ ) => const Stream<TtsOutcome>.empty() );
  } );
  tearDown( () => ctrl.close() );

  Widget host() => MaterialApp( home: Scaffold( body: TtsQueueSheet( tts: tts ) ) );

  testWidgets( 'renders current (Skip) + pending (Delete) rows with sender labels; controls call the orchestrator', ( tester ) async {
    await tester.pumpWidget( host() );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.ttsQueueSheet ) ), findsOneWidget );
    expect( find.textContaining( '1 playing · 2 queued' ), findsOneWidget );
    expect( find.byKey( const Key( '${TestKeys.ttsQueueRowPrefix}10' ) ), findsOneWidget );
    expect( find.text( 'Tiffany · playing' ), findsOneWidget );
    expect( find.text( 'pytest.runner · low' ), findsOneWidget, reason: 'system sender ⇒ id local part' );
    expect( find.byKey( const Key( TestKeys.ttsQueueSkip ) ), findsOneWidget );
    expect( find.byKey( const Key( '${TestKeys.ttsQueueDeletePrefix}11' ) ), findsOneWidget );
    expect( find.byKey( const Key( '${TestKeys.ttsQueueDeletePrefix}10' ) ), findsNothing, reason: 'current row has Skip, not Delete' );

    await tester.tap( find.byKey( const Key( TestKeys.ttsQueueSkip ) ) );
    verify( () => tts.skipCurrent() ).called( 1 );
    await tester.tap( find.byKey( const Key( '${TestKeys.ttsQueueDeletePrefix}11' ) ) );
    verify( () => tts.removeQueued( 11 ) ).called( 1 );
    await tester.tap( find.byKey( const Key( TestKeys.ttsQueueClear ) ) );
    verify( () => tts.clearQueued() ).called( 1 );
    await tester.tap( find.byKey( const Key( TestKeys.ttsQueueStopAll ) ) );
    verify( () => tts.stopAll() ).called( 1 );
  } );

  testWidgets( 'live updates: a stream emission re-renders; empty ⇒ quiet message and disabled Clear/Stop', ( tester ) async {
    await tester.pumpWidget( host() );
    await tester.pump();
    ctrl.add( const [] );
    await tester.pump();
    await tester.pump();
    expect( find.byKey( const Key( TestKeys.ttsQueueEmpty ) ), findsOneWidget );
    expect( tester.widget<TextButton>( find.byKey( const Key( TestKeys.ttsQueueClear ) ) ).onPressed, isNull );
    expect( tester.widget<IconButton>( find.byKey( const Key( TestKeys.ttsQueueStopAll ) ) ).onPressed, isNull );
    ctrl.add( [ items[ 1 ] ] );
    await tester.pump();
    await tester.pump();
    expect( find.text( 'noisy test line' ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.ttsQueueSkip ) ), findsNothing, reason: 'nothing playing ⇒ no Skip' );
  } );

  group( 'the last-message line', () {
    testWidgets( 'shows nothing before any message has arrived', ( tester ) async {
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.ttsQueueLastOutcome ) ), findsNothing );
    } );

    testWidgets( 'a message that was not spoken says why, in the error colour', ( tester ) async {
      when( () => tts.lastOutcome ).thenReturn( TtsOutcome(
        line: 'Last message not spoken: Master mute is on', problem: true, at: DateTime( 2026, 10, 10 ) ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.text( 'Last message not spoken: Master mute is on' ), findsOneWidget );
      final text = tester.widget<Text>( find.text( 'Last message not spoken: Master mute is on' ) );
      final ctx  = tester.element( find.byKey( const Key( TestKeys.ttsQueueSheet ) ) );
      expect( text.style?.color, Theme.of( ctx ).colorScheme.error );
    } );

    testWidgets( 'a new outcome replaces the line live; a normal send reads quietly', ( tester ) async {
      final out = StreamController<TtsOutcome>.broadcast();
      addTearDown( out.close );
      final stream = out.stream;
      when( () => tts.outcomeStream ).thenAnswer( ( _ ) => stream );
      when( () => tts.lastOutcome ).thenReturn( TtsOutcome(
        line: 'Held, not spoken yet: speech is paused (1 waiting)', problem: true, at: DateTime( 2026, 10, 10 ) ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.textContaining( 'speech is paused' ), findsOneWidget );

      out.add( TtsOutcome( line: 'Last message sent to the speaker', problem: false, at: DateTime( 2026, 10, 10 ) ) );
      await tester.pump();
      await tester.pump();
      expect( find.textContaining( 'speech is paused' ), findsNothing );
      final text = tester.widget<Text>( find.text( 'Last message sent to the speaker' ) );
      final ctx  = tester.element( find.byKey( const Key( TestKeys.ttsQueueSheet ) ) );
      expect( text.style?.color, isNot( Theme.of( ctx ).colorScheme.error ) );
    } );
  } );
}
