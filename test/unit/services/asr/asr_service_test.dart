import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';

class _MockDio      extends Mock implements Dio {}
class _MockRecorder extends Mock implements AudioRecorder {}

void main() {
  group( 'AsrService (S4)', () {
    late _MockDio      dio;
    late _MockRecorder recorder;
    late Directory     tempDir;
    late AsrService    asr;

    setUpAll( () {
      registerFallbackValue( FormData() );
      registerFallbackValue( Options() );
      registerFallbackValue( const RecordConfig() );
    } );

    setUp( () async {
      dio      = _MockDio();
      recorder = _MockRecorder();
      tempDir  = await Directory.systemTemp.createTemp( 'asr-test-' );
      asr      = AsrService(
        dio             : dio,
        recorder        : recorder,
        tempDirProvider : () async => tempDir,
      );

      when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
      when( () => recorder.start( any(), path: any( named: 'path' ) ) )
          .thenAnswer( ( _ ) async {} );
      when( () => recorder.cancel() ).thenAnswer( ( _ ) async {} );
    } );

    tearDown( () async {
      if ( tempDir.existsSync() ) await tempDir.delete( recursive: true );
    } );

    /// Start a capture, materialize the temp WAV the mock recorder "wrote",
    /// stub stop() to return its path. Returns the file.
    Future<File> startWithFile() async {
      await asr.startRecording();
      final path = verify( () => recorder.start( any(), path: captureAny( named: 'path' ) ) )
          .captured.single as String;
      final file = File( path )..writeAsBytesSync( [ 0x52, 0x49, 0x46, 0x46 ] );
      when( () => recorder.stop() ).thenAnswer( ( _ ) async => path );
      return file;
    }

    Response<dynamic> response( dynamic data, { int status = 200 } ) => Response(
      requestOptions : RequestOptions( path: AsrService.endpointPath ),
      data           : data,
      statusCode     : status,
    );

    test( 'AC-S4.1 — happy path: stop → multipart POST to the WAV endpoint with field name "file" → transcript', () async {
      final file = await startWithFile();
      when( () => dio.post<dynamic>(
        any(),
        data    : any( named: 'data' ),
        options : any( named: 'options' ),
      ) ).thenAnswer( ( _ ) async => response( 'Focus mode voice chat test one two three.' ) );

      final transcript = await asr.stopAndTranscribe();

      expect( transcript, 'Focus mode voice chat test one two three.' );
      final captured = verify( () => dio.post<dynamic>(
        captureAny(),
        data    : captureAny( named: 'data' ),
        options : any( named: 'options' ),
      ) ).captured;
      expect( captured[ 0 ], '/api/upload-and-transcribe-wav' );
      final form = captured[ 1 ] as FormData;
      expect( form.files.single.key, 'file', reason: 'multipart field name pinned' );
      expect( file.existsSync(), isFalse, reason: 'temp WAV deleted after success' );
    } );

    test( 'AC-S4.2 — HTTP 500 → typed AsrException with statusCode; temp file deleted', () async {
      final file = await startWithFile();
      when( () => dio.post<dynamic>(
        any(),
        data    : any( named: 'data' ),
        options : any( named: 'options' ),
      ) ).thenThrow( DioException(
        requestOptions : RequestOptions( path: AsrService.endpointPath ),
        response       : response( 'boom', status: 500 ),
        type           : DioExceptionType.badResponse,
      ) );

      await expectLater(
        asr.stopAndTranscribe(),
        throwsA( isA<AsrException>()
            .having( ( e ) => e.statusCode, 'statusCode', 500 ) ),
      );
      expect( file.existsSync(), isFalse, reason: 'temp WAV deleted after failure' );
    } );

    test( 'AC-S4.2 — network error (no response) → typed AsrException; temp file deleted', () async {
      final file = await startWithFile();
      when( () => dio.post<dynamic>(
        any(),
        data    : any( named: 'data' ),
        options : any( named: 'options' ),
      ) ).thenThrow( DioException(
        requestOptions : RequestOptions( path: AsrService.endpointPath ),
        type           : DioExceptionType.connectionError,
      ) );

      await expectLater( asr.stopAndTranscribe(), throwsA( isA<AsrException>() ) );
      expect( file.existsSync(), isFalse );
    } );

    test( 'AC-S4.2 ext (F-S4-S3-2b) — HTTP 200 with an EMPTY transcript ALSO throws; never returns the empty string', () async {
      final file = await startWithFile();
      when( () => dio.post<dynamic>(
        any(),
        data    : any( named: 'data' ),
        options : any( named: 'options' ),
      ) ).thenAnswer( ( _ ) async => response( '   ' ) );

      await expectLater(
        asr.stopAndTranscribe(),
        throwsA( isA<AsrException>()
            .having( ( e ) => e.message, 'message', contains( 'empty' ) ) ),
      );
      expect( file.existsSync(), isFalse );
    } );

    test( 'AC-S4.3 — cancel discards the recording: no upload fired, temp file removed', () async {
      final file = await startWithFile();

      await asr.cancelRecording();

      verify( () => recorder.cancel() ).called( 1 );
      verifyNever( () => dio.post<dynamic>(
        any(),
        data    : any( named: 'data' ),
        options : any( named: 'options' ),
      ) );
      expect( file.existsSync(), isFalse, reason: 'belt: service deletes even if recorder.cancel() did not' );
    } );

    test( 'denied mic permission → typed AsrException before any recorder start', () async {
      when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => false );

      await expectLater(
        asr.startRecording(),
        throwsA( isA<AsrException>()
            .having( ( e ) => e.message, 'message', contains( 'permission' ) ) ),
      );
      verifyNever( () => recorder.start( any(), path: any( named: 'path' ) ) );
    } );

    test( 'F-S4-IMPL-1 — recorder stop() THROW surfaces as the typed AsrException; temp file cleaned, no upload', () async {
      final file = await startWithFile();
      when( () => recorder.stop() ).thenThrow( Exception( 'native recorder crash' ) );

      await expectLater(
        asr.stopAndTranscribe(),
        throwsA( isA<AsrException>()
            .having( ( e ) => e.message, 'message', contains( 'failed to stop' ) ) ),
      );
      expect( file.existsSync(), isFalse );
      verifyNever( () => dio.post<dynamic>(
        any(),
        data    : any( named: 'data' ),
        options : any( named: 'options' ),
      ) );
    } );

    test( 'recorder stop() returns null and no active path → typed AsrException', () async {
      when( () => recorder.stop() ).thenAnswer( ( _ ) async => null );

      await expectLater( asr.stopAndTranscribe(), throwsA( isA<AsrException>() ) );
      verifyNever( () => dio.post<dynamic>(
        any(),
        data    : any( named: 'data' ),
        options : any( named: 'options' ),
      ) );
    } );
  } );
}
