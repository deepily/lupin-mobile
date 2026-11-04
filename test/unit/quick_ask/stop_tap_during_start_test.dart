/// A stop tap that lands while the recorder is still starting.
///
/// Starting is async: permission, config, temp dir, then the recorder.
/// Until it finished, the phase stayed `idle`.
/// So the release guard dropped the second tap and the recording kept running,
/// or a repeated press started the recorder twice.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/quick_ask/domain/earbud_taps.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

import '_quick_ask_harness.dart';

void main() {
  Future<( Harness, Completer<void> )> slowStart() async {
    final h    = Harness();
    final gate = Completer<void>();
    h.stubEmptyQueues();
    when( () => h.asr.startRecording() ).thenAnswer( ( _ ) => gate.future );
    when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'hello there' );
    await settle();
    return ( h, gate );
  }

  test( 'a stop tap during a slow start is honoured, not dropped', () async {
    final ( h, gate ) = await slowStart();

    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    h.bloc.add( const QuickAskRecordReleased() );   // second tap, recorder not up yet
    await settle();
    gate.complete();
    await settle();

    verify( () => h.asr.stopAndTranscribe() ).called( 1 );
    expect( h.bloc.state.phase,           QuickAskPhase.review );
    expect( h.bloc.state.draftTranscript, 'hello there' );
    await h.dispose();
  } );

  test( 'a repeated press during a slow start does not start the recorder twice', () async {
    final ( h, gate ) = await slowStart();

    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    gate.complete();
    await settle();

    verify( () => h.asr.startRecording() ).called( 1 );
    await h.dispose();
  } );

  test( 'the earbud single tap while starting means stop', () async {
    final ( h, gate ) = await slowStart();
    h.bloc.add( const QuickAskRecordPressed() );
    await settle();

    final action = earbudAction( EarbudGesture.single, h.bloc.state );
    expect( action.event, isA<QuickAskRecordReleased>() );

    gate.complete();
    await settle();
    await h.dispose();
  } );
}
