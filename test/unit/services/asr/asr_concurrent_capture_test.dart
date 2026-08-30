/// AC-S2.2c — `AsrService` refuses a SECOND concurrent capture, and says so.
///
/// 🔴 Why the state lives on the SERVICE and not on a caller. `AsrService` is
/// a lazy singleton (`service_locator.dart:327`) holding ONE `AudioRecorder`
/// and ONE mutable `String? _activePath`, written unconditionally by
/// `startRecording` and consumed by `stopAndTranscribe`. TWO components share
/// that instance: focus mode's `VoiceReplyField` and Quick Ask's hold-to-talk
/// button. `QuickAskBloc` knowing what IT initiated says NOTHING about a reply
/// already recording on the same recorder — a guard held by one caller is
/// structurally blind to the other.
///
/// Scope bar: this is a GUARD, not a feature. Concurrent capture stays out of
/// scope; this only makes the collision impossible and legible instead of
/// silent and lossy.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';

class _MockDio      extends Mock implements Dio {}
class _MockRecorder extends Mock implements AudioRecorder {}

void main() {
  group( 'AC-S2.2c — one recorder, one capture', () {
    late _MockRecorder recorder;
    late Directory     tempDir;
    late AsrService    asr;

    setUpAll( () {
      registerFallbackValue( const RecordConfig() );
    } );

    setUp( () async {
      recorder = _MockRecorder();
      tempDir  = await Directory.systemTemp.createTemp( 'asr-concurrent-' );
      asr      = AsrService(
        dio             : _MockDio(),
        recorder        : recorder,
        tempDirProvider : () async => tempDir,
      );
      when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
      when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( _ ) async {} );
      when( () => recorder.cancel() ).thenAnswer( ( _ ) async {} );
    } );

    tearDown( () async {
      if ( tempDir.existsSync() ) await tempDir.delete( recursive: true );
    } );

    test( 'isCapturing is false before any capture and true during one', () async {
      expect( asr.isCapturing, isFalse );
      await asr.startRecording();
      expect( asr.isCapturing, isTrue );
    } );

    test( 'a SECOND startRecording throws AsrException and says why', () async {
      await asr.startRecording();
      expect(
        () => asr.startRecording(),
        throwsA( isA<AsrException>().having(
          ( e ) => e.message, 'message', contains( 'already in progress' ) ) ),
      );
    } );

    test( '🔴 the throw happens BEFORE the recorder is touched — the first capture is not orphaned', () async {
      await asr.startRecording();
      final firstPath = verify( () => recorder.start( any(), path: captureAny( named: 'path' ) ) )
          .captured.single as String;

      try { await asr.startRecording(); } on AsrException { /* expected */ }

      // The falsifier this test exists for: guarding inside `QuickAskBloc`
      // instead lets the second start through, `_activePath` is overwritten,
      // and whichever stop fires first consumes the other's file.
      verifyNever( () => recorder.start( any(), path: any( named: 'path' ) ) );
      when( () => recorder.stop() ).thenAnswer( ( _ ) async => null );

      // `_activePath` still points at the FIRST capture, not a second one.
      File( firstPath ).writeAsBytesSync( [ 0x52, 0x49, 0x46, 0x46 ] );
      expect( asr.isCapturing, isTrue );
    } );

    test( 'the second start does not even ask for permission — it is refused at the door', () async {
      await asr.startRecording();
      clearInteractions( recorder );
      try { await asr.startRecording(); } on AsrException { /* expected */ }
      verifyNever( () => recorder.hasPermission() );
    } );

    test( 'cancelRecording releases the guard, so the next capture is allowed', () async {
      await asr.startRecording();
      expect( asr.isCapturing, isTrue );
      await asr.cancelRecording();
      expect( asr.isCapturing, isFalse );
      await asr.startRecording();          // must not throw
      expect( asr.isCapturing, isTrue );
    } );

    test( 'a recorder that fails to START leaves the guard CLEAR, not stuck', () async {
      when( () => recorder.start( any(), path: any( named: 'path' ) ) )
          .thenThrow( Exception( 'device busy' ) );
      try { await asr.startRecording(); } on AsrException { /* expected */ }
      expect( asr.isCapturing, isFalse,
          reason: 'a stuck guard would lock the user out of recording for the rest of the session' );
    } );

    test( 'a DENIED permission leaves the guard clear too', () async {
      when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => false );
      try { await asr.startRecording(); } on AsrException { /* expected */ }
      expect( asr.isCapturing, isFalse );
    } );
  } );
}
