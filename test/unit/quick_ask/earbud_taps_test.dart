/// Earbud presses become a tap or a double tap, each doing what its on-screen button does.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/quick_ask/data/hands_free_cues.dart';
import 'package:lupin_mobile/features/quick_ask/domain/earbud_taps.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

class _MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  group( 'EarbudTapReader', () {
    late List<EarbudGesture> seen;
    late EarbudTapReader     reader;

    setUp( () {
      seen   = [];
      reader = EarbudTapReader( onGesture: seen.add );
    } );

    test( 'a lone press is a single tap, after the window', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.media );
      clock.elapse( const Duration( milliseconds: 399 ) );
      expect( seen, isEmpty );
      clock.elapse( const Duration( milliseconds: 1 ) );
      expect( seen, [ EarbudGesture.single ] );
    } ) );

    test( 'two presses inside the window are one double tap and no single', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.media );
      clock.elapse( const Duration( milliseconds: 250 ) );
      reader.press( MediaButton.media );
      clock.elapse( const Duration( seconds: 1 ) );
      expect( seen, [ EarbudGesture.double ] );
    } ) );

    test( 'two presses further apart are two single taps', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.media );
      clock.elapse( const Duration( milliseconds: 500 ) );
      reader.press( MediaButton.media );
      clock.elapse( const Duration( milliseconds: 500 ) );
      expect( seen, [ EarbudGesture.single, EarbudGesture.single ] );
    } ) );

    test( 'a "next track" press is a double tap at once', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.next );
      expect( seen, [ EarbudGesture.double ] );
    } ) );

    test( 'a play press just after "next track" is its echo and reports nothing', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.next );
      clock.elapse( const Duration( milliseconds: 299 ) );
      reader.press( MediaButton.media );
      clock.elapse( const Duration( seconds: 1 ) );
      expect( seen, [ EarbudGesture.double ] );
    } ) );

    test( 'a play press once the echo window has passed is a single tap again', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.next );
      clock.elapse( EarbudTapReader.defaultEchoWindow );
      reader.press( MediaButton.media );
      clock.elapse( EarbudTapReader.defaultWindow );
      expect( seen, [ EarbudGesture.double, EarbudGesture.single ] );
    } ) );

    test( 'a "next track" press drops a press still waiting', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.media );
      reader.press( MediaButton.next );
      clock.elapse( const Duration( seconds: 1 ) );
      expect( seen, [ EarbudGesture.double ] );
    } ) );

    test( 'a "previous track" press is ignored', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.previous );
      clock.elapse( const Duration( seconds: 1 ) );
      expect( seen, isEmpty );
    } ) );

    test( 'dispose drops a press still waiting', () => fakeAsync( ( clock ) {
      reader.press( MediaButton.media );
      reader.dispose();
      clock.elapse( const Duration( seconds: 1 ) );
      expect( seen, isEmpty );
    } ) );
  } );

  group( 'earbudAction', () {
    const idle      = QuickAskState( connected: true );
    const recording = QuickAskState( connected: true, phase: QuickAskPhase.recording, capturing: true );
    const held      = QuickAskState( connected: true, phase: QuickAskPhase.review, draftTranscript: 'what time is it' );
    const offline   = QuickAskState();

    test( 'a tap when the microphone is live starts recording', () {
      expect( earbudAction( EarbudGesture.single, idle ),
          ( event: const QuickAskRecordPressed(), cue: HandsFreeCue.started ) );
    } );

    test( 'a tap while recording stops it', () {
      expect( earbudAction( EarbudGesture.single, recording ),
          ( event: const QuickAskRecordReleased(), cue: HandsFreeCue.stopped ) );
    } );

    test( 'a double tap while recording also stops it, so the question is not lost', () {
      expect( earbudAction( EarbudGesture.double, recording ),
          ( event: const QuickAskRecordReleased(), cue: HandsFreeCue.stopped ) );
    } );

    test( 'a double tap with a held transcript sends it', () {
      expect( earbudAction( EarbudGesture.double, held ),
          ( event: const QuickAskDraftSent(), cue: HandsFreeCue.sent ) );
    } );

    test( 'a double tap with nothing held sends nothing', () {
      expect( earbudAction( EarbudGesture.double, idle ), ( event: null, cue: HandsFreeCue.refused ) );
    } );

    test( 'a tap while a transcript is held does not start over it', () {
      expect( earbudAction( EarbudGesture.single, held ), ( event: null, cue: HandsFreeCue.refused ) );
    } );

    test( 'a tap while recording is blocked only plays the refusal', () {
      expect( earbudAction( EarbudGesture.single, offline ), ( event: null, cue: HandsFreeCue.refused ) );
      const busy = QuickAskState( connected: true, liveJobId: 'job-1', phase: QuickAskPhase.waiting );
      expect( earbudAction( EarbudGesture.single, busy ), ( event: null, cue: HandsFreeCue.refused ) );
    } );
  } );

  group( 'ToneCuePlayer', () {
    late _MockAudioPlayer   player;
    late int                built;
    late List<HandsFreeCue> asked;
    late ToneCuePlayer      cues;
    late Completer<void>    playing;

    setUp( () {
      player  = _MockAudioPlayer();
      built   = 0;
      asked   = [];
      playing = Completer<void>();
      when( () => player.stop() ).thenAnswer( ( _ ) async {} );
      when( () => player.setFilePath( any() ) ).thenAnswer( ( _ ) async => const Duration( milliseconds: 60 ) );
      // A real just_audio play() completes only when playback stops.
      when( () => player.play() ).thenAnswer( ( _ ) => playing.future );
      cues = ToneCuePlayer(
        create   : () { built++; return player; },
        toneFile : ( cue ) async { asked.add( cue ); return '/tmp/${ cue.name }.wav'; },
      );
    } );

    test( 'no player is built until the first cue', () {
      expect( built, 0 );
    } );

    test( 'a cue stops the one still playing, loads its own file and plays it', () async {
      await cues.play( HandsFreeCue.started );
      await cues.play( HandsFreeCue.stopped );
      verifyInOrder( [
        () => player.stop(), () => player.setFilePath( '/tmp/started.wav' ), () => player.play(),
        () => player.stop(), () => player.setFilePath( '/tmp/stopped.wav' ), () => player.play(),
      ] );
      expect( asked, [ HandsFreeCue.started, HandsFreeCue.stopped ] );
      expect( built, 1 );
    } );

    test( 'play returns without waiting for the tone to end', () async {
      await cues.play( HandsFreeCue.ready ).timeout( const Duration( seconds: 1 ) );
      expect( playing.isCompleted, isFalse );
    } );

    test( 'a tone that fails while playing is not thrown into the next cue', () async {
      await cues.play( HandsFreeCue.ready );
      playing.completeError( StateError( 'no audio' ) );
      await pumpEventQueue();
      playing = Completer<void>();
      await cues.play( HandsFreeCue.started );
      verify( () => player.play() ).called( 2 );
    } );
  } );

  group( 'CueTones', () {
    test( 'each cue is a mono 16-bit PCM WAV of the expected length', () {
      for ( final cue in HandsFreeCue.values ) {
        final bytes = CueTones.wav( cue );
        final view  = ByteData.view( bytes.buffer );
        expect( String.fromCharCodes( bytes.sublist( 0, 4 ) ),  'RIFF', reason: '$cue' );
        expect( String.fromCharCodes( bytes.sublist( 8, 12 ) ), 'WAVE' );
        expect( view.getUint16( 22, Endian.little ), 1 );
        expect( view.getUint32( 24, Endian.little ), CueTones.sampleRate );
        expect( view.getUint16( 34, Endian.little ), 16 );
        final seconds = CueTones.notes[ cue ]!.fold<double>( 0, ( sum, n ) => sum + n.$2 );
        final samples = CueTones.notes[ cue ]!
            .fold<int>( 0, ( sum, n ) => sum + ( CueTones.sampleRate * n.$2 ).round() );
        expect( view.getUint32( 40, Endian.little ), samples * 2 );
        expect( bytes.length, 44 + samples * 2 );
        expect( seconds, lessThan( 0.4 ), reason: 'a cue must be short' );
      }
    } );

    test( 'notes start and end silent, so they do not click', () {
      final view = ByteData.view( CueTones.wav( HandsFreeCue.refused ).buffer );
      final last = ( view.lengthInBytes - 44 ) ~/ 2 - 1;
      expect( view.getInt16( 44, Endian.little ), 0 );
      expect( view.getInt16( 44 + last * 2, Endian.little ), 0 );
    } );

    test( 'the four cues sound different', () {
      final tones = HandsFreeCue.values.map( ( c ) => CueTones.notes[ c ].toString() ).toSet();
      expect( tones, hasLength( HandsFreeCue.values.length ) );
    } );
  } );
}
