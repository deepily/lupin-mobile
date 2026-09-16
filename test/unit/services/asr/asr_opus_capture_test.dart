import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';

class _MockDio      extends Mock implements Dio {}
class _MockRecorder extends Mock implements AudioRecorder {}

/// Row 9b1f7701 — the recorder records Ogg/Opus at 32 kbps, and a device
/// without an Opus encoder records the WAV it always did.
///
/// The format is pinned here on purpose: it was chosen on a measurement
/// (0.57% word error rate against WAV on real phone recordings), and a quiet
/// edit back to WAV, or to a bitrate nobody measured, should fail a test
/// rather than a user's upload budget.
void main() {
  late _MockDio      dio;
  late _MockRecorder recorder;
  late Directory     tempDir;

  setUpAll( () {
    registerFallbackValue( FormData() );
    registerFallbackValue( Options() );
    registerFallbackValue( const RecordConfig() );
    registerFallbackValue( AudioEncoder.wav );
  } );

  setUp( () async {
    dio      = _MockDio();
    recorder = _MockRecorder();
    tempDir  = await Directory.systemTemp.createTemp( 'asr-opus-' );
    when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
    when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( _ ) async {} );
    when( () => dio.post<dynamic>(
      any(),
      data    : any( named: 'data' ),
      options : any( named: 'options' ),
    ) ).thenAnswer( ( _ ) async => Response(
      requestOptions : RequestOptions( path: AsrService.endpointPath ),
      data           : { 'transcription': 'what is two plus two', 'trace': { 'stt_ms': 9.0, 'upload_bytes': 4 } },
      statusCode     : 200,
    ) );
  } );

  tearDown( () async {
    if ( tempDir.existsSync() ) await tempDir.delete( recursive: true );
  } );

  AsrService build( { Future<bool> Function()? opusSupported } ) => AsrService(
    dio             : dio,
    recorder        : recorder,
    tempDirProvider : () async => tempDir,
    opusSupported   : opusSupported,
  );

  /// Start, capture the config and path handed to the recorder, make the
  /// file exist, and stub stop() to return it.
  Future<( RecordConfig, String )> start( AsrService asr ) async {
    await asr.startRecording();
    final captured = verify( () => recorder.start( captureAny(), path: captureAny( named: 'path' ) ) ).captured;
    final path     = captured[ 1 ] as String;
    File( path ).writeAsBytesSync( [ 0x4f, 0x67, 0x67, 0x53 ] );
    when( () => recorder.stop() ).thenAnswer( ( _ ) async => path );
    return ( captured[ 0 ] as RecordConfig, path );
  }

  group( 'the measured format is pinned', () {
    test( 'recordConfig is Opus, mono, 48 kHz, 32 kbps', () {
      const cfg = AsrService.recordConfig;
      expect( cfg.encoder,     AudioEncoder.opus );
      expect( cfg.numChannels, 1 );
      expect( cfg.bitRate,     32000, reason: 'the bitrate the accuracy check measured' );
      expect( cfg.sampleRate,  48000, reason: "Android's Opus encoder takes 8/12/16/24/48 kHz only" );
    } );

    test( 'the fallback is the WAV the app shipped before the switch', () {
      const cfg = AsrService.wavFallbackConfig;
      expect( cfg.encoder,     AudioEncoder.wav );
      expect( cfg.sampleRate,  44100 );
      expect( cfg.numChannels, 1 );
    } );

    test( 'Opus files are .ogg, everything else .wav', () {
      expect( AsrService.fileExtensionFor( AudioEncoder.opus ), 'ogg' );
      expect( AsrService.fileExtensionFor( AudioEncoder.wav ),  'wav' );
    } );
  } );

  group( 'a device that can encode Opus', () {
    test( 'records with recordConfig into an .ogg file', () async {
      final ( config, path ) = await start( build( opusSupported: () async => true ) );
      expect( config, same( AsrService.recordConfig ) );
      expect( path, endsWith( '.ogg' ) );
    } );

    test( 'uploads under an .ogg filename, because the server keeps the extension', () async {
      final asr = build( opusSupported: () async => true );
      await start( asr );

      await asr.stopAndTranscribe();

      final form = verify( () => dio.post<dynamic>(
        any(),
        data    : captureAny( named: 'data' ),
        options : any( named: 'options' ),
      ) ).captured.single as FormData;
      expect( form.files.single.value.filename, 'voice-reply.ogg' );
    } );

    test( 'asks about Opus support once, not on every capture', () async {
      var asks = 0;
      final asr = build( opusSupported: () async { asks++; return true; } );
      for ( var i = 0; i < 3; i++ ) {
        await start( asr );
        clearInteractions( recorder );
        await asr.stopToFile();
      }
      expect( asks, 1 );
    } );

    test( 'by default the question goes to the recorder itself', () async {
      when( () => recorder.isEncoderSupported( AudioEncoder.opus ) ).thenAnswer( ( _ ) async => true );
      final ( config, _ ) = await start( build() );
      verify( () => recorder.isEncoderSupported( AudioEncoder.opus ) ).called( 1 );
      expect( config.encoder, AudioEncoder.opus );
    } );
  } );

  group( 'a device without an Opus encoder', () {
    test( 'records the WAV fallback into a .wav file', () async {
      final ( config, path ) = await start( build( opusSupported: () async => false ) );
      expect( config, same( AsrService.wavFallbackConfig ) );
      expect( path, endsWith( '.wav' ) );
    } );

    test( 'uploads under a .wav filename', () async {
      final asr = build( opusSupported: () async => false );
      await start( asr );

      await asr.stopAndTranscribe();

      final form = verify( () => dio.post<dynamic>(
        any(),
        data    : captureAny( named: 'data' ),
        options : any( named: 'options' ),
      ) ).captured.single as FormData;
      expect( form.files.single.value.filename, 'voice-reply.wav' );
    } );

    test( 'a support check that throws counts as no Opus, so capture still works', () async {
      final ( config, _ ) = await start( build( opusSupported: () async => throw Exception( 'channel gone' ) ) );
      expect( config.encoder, AudioEncoder.wav );
    } );
  } );

  test( 'a kept Opus recording keeps its .ogg extension', () {
    final t = DateTime.utc( 2026, 9, 16, 22, 30, 1, 2 );
    expect( AsrService.keptFileNameFor( t, 3, extension: 'ogg' ), 'rec-20260916-223001002Z-3.ogg' );
  } );
}
