/// A recorder start that throws must not leave Quick Ask stuck at `starting`.
///
/// The failing case was found in review, using a non-recorder error such as a missing temp dir.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

import '_quick_ask_harness.dart';

void main() {
  test( 'a non-recorder throw during start returns to idle with an error, and a later press works', () async {
    final h = Harness();
    h.stubEmptyQueues();
    when( () => h.asr.startRecording() ).thenThrow( StateError( 'temp dir unavailable' ) );
    await settle();

    h.bloc.add( const QuickAskRecordPressed() );
    h.bloc.add( const QuickAskRecordReleased() );   // a held stop must not outlive the failed start
    await settle();

    expect( h.bloc.state.phase,        QuickAskPhase.idle );
    expect( h.bloc.state.errorMessage, isNotNull );

    when( () => h.asr.startRecording() ).thenAnswer( ( _ ) async {} );
    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    expect( h.bloc.state.phase, QuickAskPhase.recording );
    await h.dispose();
  } );
}
