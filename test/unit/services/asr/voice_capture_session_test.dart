/// Row 0b40272e — the shared record → transcribe core.
///
/// Rick asked whether focus mode runs a second recording implementation. It
/// did not: both composers already drove the same AsrService. What existed
/// twice was the wrapper — permission, cancel epoch, error text, blank guard —
/// and the copies had drifted, so only Quick Ask said "did not catch
/// anything". These tests pin the one wrapper both now call.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/asr/voice_capture_session.dart';

class _MockAsr extends Mock implements AsrService {}

void main() {
  late _MockAsr asr;

  VoiceCaptureSession session( { Future<bool> Function()? permission } ) =>
      VoiceCaptureSession(
        asr               : asr,
        requestPermission : permission ?? () async => true,
      );

  setUp( () {
    asr = _MockAsr();
    when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
    when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
    when( () => asr.isCapturing       ).thenReturn( false );
  } );

  group( 'start', () {
    test( 'asks for the microphone BEFORE touching the recorder', () async {
      final calls = <String>[];
      when( () => asr.startRecording() ).thenAnswer( ( _ ) async => calls.add( 'record' ) );

      final s = session( permission: () async { calls.add( 'ask' ); return true; } );
      final start = await s.start();

      expect( start.started, isTrue );
      expect( calls, [ 'ask', 'record' ],
          reason: 'a fresh install refuses a user who was never asked' );
    } );

    test( 'a refusal names the fix and records nothing', () async {
      final start = await session( permission: () async => false ).start();

      expect( start.started, isFalse );
      expect( start.errorMessage, VoiceCaptureSession.permissionDeniedMessage );
      expect( start.errorMessage, contains( 'system settings' ) );
      verifyNever( () => asr.startRecording() );
    } );

    test( 'a recorder that throws surfaces its own message', () async {
      when( () => asr.startRecording() )
          .thenThrow( const AsrException( 'Recorder busy' ) );

      final start = await session().start();

      expect( start.started, isFalse );
      expect( start.errorMessage, 'Recorder busy' );
    } );

    test( 'a cancel during the permission prompt is stale, not an error', () async {
      final gate = Completer<bool>();
      final s    = session( permission: () => gate.future );

      final pending = s.start();
      s.cancel();
      gate.complete( true );
      final start = await pending;

      expect( start.isStale, isTrue );
      expect( start.started, isFalse );
      expect( start.errorMessage, isNull, reason: 'nothing to tell the user about' );
    } );
  } );

  group( 'stopAndTranscribe', () {
    test( 'speech comes back as the transcript', () async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'hello from whisper' );

      final capture = await session().stopAndTranscribe();

      expect( capture.wasHeard,    isTrue );
      expect( capture.transcript,  'hello from whisper' );
      expect( capture.errorMessage, isNull );
    } );

    test( 'a blank transcript is an ERROR, not an empty review box', () async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => '   \n  ' );

      final capture = await session().stopAndTranscribe();

      expect( capture.wasHeard,     isFalse );
      expect( capture.errorMessage, VoiceCaptureSession.nothingHeardMessage );
      expect( capture.isStale,      isFalse,
          reason: 'the user did nothing wrong and nothing was cancelled' );
    } );

    test( 'a failed upload surfaces the message and is not stale', () async {
      when( () => asr.stopAndTranscribe() )
          .thenThrow( const AsrException( 'Upload failed: 401' ) );

      final capture = await session().stopAndTranscribe();

      expect( capture.errorMessage, 'Upload failed: 401' );
      expect( capture.isStale,      isFalse );
    } );

    test( 'a cancel mid-upload drops the result — no transcript, no error', () async {
      final gate = Completer<String>();
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );
      final s = session();

      final pending = s.stopAndTranscribe();
      s.cancel();
      gate.complete( 'late transcript' );
      final capture = await pending;

      expect( capture.isStale,      isTrue );
      expect( capture.transcript,   isNull );
      expect( capture.errorMessage, isNull );
    } );

    test( 'a cancel mid-upload drops a FAILURE too', () async {
      final gate = Completer<String>();
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );
      final s = session();

      final pending = s.stopAndTranscribe();
      s.cancel();
      gate.completeError( const AsrException( 'too late to matter' ) );
      final capture = await pending;

      expect( capture.isStale,      isTrue );
      expect( capture.errorMessage, isNull );
    } );
  } );

  group( 'cancel', () {
    test( 'cancel discards the recording and moves the epoch', () async {
      final s     = session();
      final start = s.epoch;

      s.cancel();

      verify( () => asr.cancelRecording() ).called( 1 );
      expect( s.epoch, greaterThan( start ) );
    } );

    test( 'cancelAwaiting waits for the recorder, so isCapturing can be reported', () async {
      final stopped = Completer<void>();
      when( () => asr.cancelRecording() ).thenAnswer( ( _ ) => stopped.future );
      final s = session();

      var done = false;
      final pending = s.cancelAwaiting().then( ( _ ) => done = true );
      await Future<void>.delayed( Duration.zero );
      expect( done, isFalse, reason: 'still waiting on the recorder' );

      stopped.complete();
      await pending;
      expect( done, isTrue );
    } );

    test( 'invalidate makes work stale WITHOUT stopping a recorder', () async {
      final s     = session();
      final start = s.epoch;

      s.invalidate();

      expect( s.epoch, greaterThan( start ) );
      verifyNever( () => asr.cancelRecording() );
    } );
  } );
}
