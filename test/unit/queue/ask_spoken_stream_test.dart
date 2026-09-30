/// Plan rev 14 §3.4, the rows tagged B — `QueueRepository.askSpoken`, the
/// NDJSON reader for `POST /api/v2/ask-audio`.
///
/// 🔴 SB4 — every body here is a REAL byte stream,
/// `ResponseBody( Stream.fromIterable( chunks ), status )`. The existing
/// `_SequenceAdapter` (`auth_interceptor_test.dart:12-33`) is borrowed for its
/// adapter SHAPE only: its bodies come from `ResponseBody.fromString`, which
/// yields one chunk and so can never split a line. There is no streaming
/// prior art in this repo; the chunked half is new.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/auth/auth_interceptor.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';
import 'package:lupin_mobile/services/auth/auth_token_provider.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import '../../_helpers/fixture_loader.dart';

typedef _Responder = ResponseBody Function( RequestOptions options );

class _MockRecorder extends Mock implements AudioRecorder {}
class _MockDio      extends Mock implements Dio {}

/// One captured request: its options, the body object AT SEND TIME, and the
/// bytes that actually went out. `data` is snapshotted because the auth retry
/// replays the SAME `RequestOptions` object, so `options.data` read later
/// shows only the last attempt's body.
class _Sent {
  final RequestOptions options;
  final Object?        data;
  final Uint8List      bytes;
  _Sent( this.options, this.bytes ) : data = options.data;
  String get text => latin1.decode( bytes );
}

/// `_SequenceAdapter`'s shape, plus it DRAINS the request stream so a test can
/// read the multipart body that was really sent.
class _StreamingAdapter implements HttpClientAdapter {
  final List<_Responder> responses;
  final List<_Sent>      sent = [];
  int _idx = 0;

  _StreamingAdapter( this.responses );

  @override
  Future<ResponseBody> fetch(
    RequestOptions     options,
    Stream<Uint8List>? requestStream,
    Future<void>?      cancelFuture,
  ) async {
    final builder = BytesBuilder();
    if ( requestStream != null ) {
      await for ( final chunk in requestStream ) {
        builder.add( chunk );
      }
    }
    sent.add( _Sent( options, builder.takeBytes() ) );
    if ( _idx >= responses.length ) return ResponseBody.fromString( 'no more responses', 500 );
    return responses[ _idx++ ]( options );
  }

  @override
  void close( { bool force = false } ) {}
}

Uint8List _bytes( String s ) => Uint8List.fromList( utf8.encode( s ) );

/// A 200 NDJSON body delivered as the given chunks, in order.
ResponseBody _chunked( List<Uint8List> chunks, { int status = 200 } ) => ResponseBody(
  Stream.fromIterable( chunks ),
  status,
  headers: { Headers.contentTypeHeader: [ 'application/x-ndjson' ] },
);

/// A body that delivers `before` and then fails like a dropped connection.
ResponseBody _breaksAfter( String before ) {
  final ctrl = StreamController<Uint8List>();
  ctrl.onListen = () {
    if ( before.isNotEmpty ) ctrl.add( _bytes( before ) );
    ctrl.addError( const SocketException( 'Connection reset by peer' ) );
    ctrl.close();
  };
  return ResponseBody( ctrl.stream, 200 );
}

ResponseBody _jsonError( int status, Map<String, dynamic> body ) => ResponseBody.fromString(
  jsonEncode( body ),
  status,
  headers: { Headers.contentTypeHeader: [ Headers.jsonContentType ] },
);

const _transcriptLine = '{"type":"transcript","transcription":"what\'s the weather in Boston","trace":{"stt_ms":271.4,"upload_bytes":249000}}\n';
const _askLine        = '{"type":"ask","result":{"path":"agent","status":"waiting","route_reason":"args_complete","job_id":"4f2a9c7e1b3d","trace_id":"tr-5c1e8a20"}}\n';
const _errorLine      = '{"type":"error","stage":"ask","detail":"flow exploded"}\n';

/// §3.2's end-of-stream invariant, checked on every scenario: the stream
/// completes WITHOUT throwing, and emits exactly one terminal event, last.
Future<List<SpokenAskEvent>> _drain( Stream<SpokenAskEvent> s ) async {
  final events = await s.toList();   // an error event would throw here
  expect( events.where( ( e ) => e.isTerminal ).length, 1,
      reason: 'exactly one terminal event, got $events' );
  expect( events.last.isTerminal, isTrue, reason: 'the terminal event is last: $events' );
  return events;
}

void main() {
  late Directory tempDir;
  late String    audioPath;

  setUp( () async {
    tempDir   = await Directory.systemTemp.createTemp( 'ask-spoken-' );
    audioPath = '${tempDir.path}/asr-reply-123.ogg';
    File( audioPath ).writeAsBytesSync( utf8.encode( 'OGG-AUDIO-BYTES' ) );
    clearAccessToken();
  } );

  tearDown( () async {
    clearAccessToken();
    if ( tempDir.existsSync() ) await tempDir.delete( recursive: true );
  } );

  ( QueueRepository, _StreamingAdapter ) build( List<_Responder> responses ) {
    final dio     = Dio( BaseOptions( baseUrl: 'http://test' ) );
    final adapter = _StreamingAdapter( responses );
    dio.httpClientAdapter = adapter;
    return ( QueueRepository( dio ), adapter );
  }

  group( 'askSpoken — parser on every §3.2 row', () {
    test( 'two lines → Transcript then Result', () async {
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( _transcriptLine ), _bytes( _askLine ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events, hasLength( 2 ) );
      expect( events[ 0 ], const SpokenAskTranscript( "what's the weather in Boston" ) );
      final result = events[ 1 ] as SpokenAskResult;
      expect( result.response.jobId, '4f2a9c7e1b3d' );
      expect( result.response.status, 'waiting' );
    } );

    test( 'a line split across byte chunks mid-line, and mid-character, still parses', () async {
      // "é" is two UTF-8 bytes; the first split falls BETWEEN them.
      final whole = _bytes( '{"type":"transcript","transcription":"café au lait"}\n$_askLine' );
      final e     = whole.indexOf( 0xC3 );                     // first byte of é
      final mid2  = whole.length - 40;                         // inside the ask line
      final chunks = [
        whole.sublist( 0, e + 1 ),
        whole.sublist( e + 1, mid2 ),
        whole.sublist( mid2 ),
      ];
      expect( utf8.decode( chunks[ 0 ], allowMalformed: true ), endsWith( '\uFFFD' ),
          reason: 'positive control: the first chunk really ends mid-character' );
      expect( utf8.decode( chunks[ 0 ], allowMalformed: true ), isNot( contains( '\n' ) ),
          reason: 'positive control: the first chunk really ends mid-line' );

      final ( repo, _ ) = build( [ ( _ ) => _chunked( chunks ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.first, const SpokenAskTranscript( 'café au lait' ) );
      expect( ( events.last as SpokenAskResult ).response.traceId, 'tr-5c1e8a20' );
    } );

    test( 'the contract body split at EVERY byte offset parses the same', () async {
      final body = _bytes( loadFixture( 'asr/ask_audio_ndjson_contract.json' )[ 'body' ] as String );
      for ( var cut = 1; cut < body.length; cut++ ) {
        final ( repo, _ ) = build( [ ( _ ) => _chunked( [ body.sublist( 0, cut ), body.sublist( cut ) ] ) ] );
        final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
        expect( events.map( ( e ) => e.runtimeType ).toList(), [ SpokenAskTranscript, SpokenAskResult ],
            reason: 'split at byte $cut' );
      }
    } );

    test( 'error line → Transcript then Failed( detail )', () async {
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( _transcriptLine + _errorLine ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events, [
        const SpokenAskTranscript( "what's the weather in Boston" ),
        const SpokenAskFailed( 'flow exploded' ),
      ] );
    } );

    test( 'body closes before any line → Failed', () async {
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events, [ const SpokenAskFailed( 'closed before transcript' ) ] );
    } );

    test( 'body closes after the transcript with no second line → CutOff', () async {
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( _transcriptLine ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events, [
        const SpokenAskTranscript( "what's the weather in Boston" ),
        const SpokenAskCutOff( "what's the weather in Boston" ),
      ] );
    } );

    test( 'body closes after a PARTIAL second line → CutOff', () async {
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( _transcriptLine + _askLine.substring( 0, 30 ) ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.last, const SpokenAskCutOff( "what's the weather in Boston" ) );
    } );

    test( 'malformed line BEFORE the transcript → Failed', () async {
      // A VALID transcript and ask follow the bad line: a reader that skipped
      // it would emit Transcript + Result, and this row would catch that.
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( 'not json\n$_transcriptLine$_askLine' ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events, hasLength( 1 ) );
      expect( events.single, isA<SpokenAskFailed>() );
      expect( ( events.single as SpokenAskFailed ).statusCode, isNull );
    } );

    test( 'a well-formed but out-of-order first line (ask before transcript) → Failed', () async {
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( _askLine + _transcriptLine ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.single, isA<SpokenAskFailed>() );
    } );

    test( 'malformed line AFTER the transcript → CutOff', () async {
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( '$_transcriptLine{"type":"ask","result":\n' ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.last, const SpokenAskCutOff( "what's the weather in Boston" ) );
    } );

    test( 'an ask line whose result AskResponse cannot parse → CutOff', () async {
      // `path` and `status` are required by AskResponse.fromJson.
      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( '$_transcriptLine{"type":"ask","result":{"trace_id":"x"}}\n' ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.last, const SpokenAskCutOff( "what's the weather in Boston" ) );
    } );

    test( 'network error mid-body BEFORE the transcript → Failed', () async {
      final ( repo, _ ) = build( [ ( _ ) => _breaksAfter( '{"type":"trans' ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.single, isA<SpokenAskFailed>() );
    } );

    test( 'network error mid-body AFTER the transcript → CutOff', () async {
      final ( repo, _ ) = build( [ ( _ ) => _breaksAfter( '$_transcriptLine{"type":"as' ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events, [
        const SpokenAskTranscript( "what's the weather in Boston" ),
        const SpokenAskCutOff( "what's the weather in Boston" ),
      ] );
    } );

    test( 'non-200 → Failed with the server detail AND the status code', () async {
      final ( repo, _ ) = build( [ ( _ ) => _jsonError( 422, { 'detail': 'No speech was recognised, so nothing was asked.' } ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events, [ const SpokenAskFailed( 'No speech was recognised, so nothing was asked.', statusCode: 422 ) ] );
    } );

    test( 'non-200 with a non-JSON body → Failed still carries the status code', () async {
      final ( repo, _ ) = build( [ ( _ ) => ResponseBody.fromString( 'Bad Gateway', 502 ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( ( events.single as SpokenAskFailed ).statusCode, 502 );
    } );

    test( 'never throws: a connection failure before any response → Failed, no status', () async {
      final ( repo, _ ) = build( [
        ( o ) => throw DioException.connectionError( requestOptions: o, reason: 'refused' ),
      ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.single, isA<SpokenAskFailed>() );
      expect( ( events.single as SpokenAskFailed ).statusCode, isNull );
    } );

    test( 'never throws: a recording that is missing → Failed, and nothing was sent', () async {
      final ( repo, adapter ) = build( [ ( _ ) => _chunked( [ _bytes( _transcriptLine + _askLine ) ] ) ] );
      final events = await _drain( repo.askSpoken( '${tempDir.path}/gone.wav', 'ws-1' ) );
      expect( events.single, isA<SpokenAskFailed>() );
      expect( adapter.sent, isEmpty );
    } );

    test( 'lazy: no request fires until the stream is listened to', () async {
      final ( repo, adapter ) = build( [ ( _ ) => _chunked( [ _bytes( _transcriptLine + _askLine ) ] ) ] );
      final stream = repo.askSpoken( audioPath, 'ws-1' );
      await Future<void>.delayed( Duration.zero );
      expect( adapter.sent, isEmpty );
      await _drain( stream );
      expect( adapter.sent, hasLength( 1 ) );
    } );
  } );

  group( 'askSpoken — the OUTGOING request (B-J1 + CB1)', () {
    test( 'websocket_id rides the QUERY STRING, the field is `file`, the filename keeps its real extension', () async {
      final ( repo, adapter ) = build( [ ( _ ) => _chunked( [ _bytes( _transcriptLine + _askLine ) ] ) ] );
      await _drain( repo.askSpoken( audioPath, 'ws-abc-123' ) );

      final sent = adapter.sent.single;
      expect( sent.options.method, 'POST' );
      expect( sent.options.path, '/api/v2/ask-audio' );
      expect( sent.options.uri.queryParameters[ 'websocket_id' ], 'ws-abc-123' );
      expect( sent.options.responseType, ResponseType.stream );
      expect( sent.options.receiveTimeout, QueueRepository.askReceiveTimeout );

      final form = sent.options.data as FormData;
      expect( form.fields.map( ( f ) => f.key ), isNot( contains( 'websocket_id' ) ),
          reason: 'a form-sent websocket_id is silently ignored by the server (§2.1 CB1)' );
      expect( form.files.single.key, 'file' );
      expect( form.files.single.value.filename, 'asr-reply-123.ogg' );

      // The wire itself, not only the object that built it.
      expect( sent.text, contains( 'name="file"; filename="asr-reply-123.ogg"' ) );
      expect( sent.text, contains( 'OGG-AUDIO-BYTES' ) );
      expect( sent.text, isNot( contains( 'websocket_id' ) ) );
    } );
  } );

  group( 'askSpoken — contract replay', () {
    test( 'the committed lupin fixture parses to Transcript, then a Result with jobId and traceId', () async {
      final contract = loadFixture( 'asr/ask_audio_ndjson_contract.json' );
      expect( contract[ 'endpoint' ], 'POST /api/v2/ask-audio' );
      expect( contract[ 'media_type' ], 'application/x-ndjson' );

      final ( repo, _ ) = build( [ ( _ ) => _chunked( [ _bytes( contract[ 'body' ] as String ) ] ) ] );
      final events = await _drain( repo.askSpoken( audioPath, 'ws-1' ) );
      expect( events.first, const SpokenAskTranscript( "what's the weather in Boston" ) );
      final res = ( events.last as SpokenAskResult ).response;
      expect( res.jobId, '4f2a9c7e1b3d' );
      expect( res.traceId, 'tr-5c1e8a20' );
      expect( res.routeReason, 'args_complete' );
      expect( res.isWaiting, isTrue );
    } );
  } );

  group( 'askSpoken — 401 then retry actually replays (CB4, ruled "retry invisibly")', () {
    test( 'the retry carries a fresh, unconsumed multipart body and the stream still yields Transcript then Result', () async {
      setAccessToken( 'stale' );
      var refreshFailed = 0;
      final dio     = Dio( BaseOptions( baseUrl: 'http://test' ) );
      final adapter = _StreamingAdapter( [
        ( _ ) => _jsonError( 401, { 'detail': 'expired' } ),                    // original POST
        ( _ ) => jsonBodyFromFixture( 'auth/refresh_response.json' ),           // /auth/refresh
        ( _ ) => _chunked( [ _bytes( _transcriptLine ), _bytes( _askLine ) ] ), // retried POST
      ] );
      dio.httpClientAdapter = adapter;
      dio.interceptors.add( AuthInterceptor(
        dio              : dio,
        repo             : AuthRepository( dio ),
        readRefreshToken : () async => 'old-ref',
        onTokensRotated  : ( _ ) async {},
        onRefreshFailed  : () async => refreshFailed++,
      ) );

      final events = await _drain( QueueRepository( dio ).askSpoken( audioPath, 'ws-1' ) );

      expect( events.map( ( e ) => e.runtimeType ).toList(), [ SpokenAskTranscript, SpokenAskResult ] );
      expect( refreshFailed, 0, reason: 'the retry must not read as a refresh failure' );
      expect( adapter.sent, hasLength( 3 ) );
      final first = adapter.sent[ 0 ];
      final retry = adapter.sent[ 2 ];
      expect( retry.options.path, '/api/v2/ask-audio' );
      expect( retry.options.headers[ 'Authorization' ], 'Bearer fixture_access_token' );
      expect( retry.options.uri.queryParameters[ 'websocket_id' ], 'ws-1' );
      expect( retry.data, isA<FormData>() );
      expect( identical( retry.data, first.data ), isFalse,
          reason: 'the retry must send a NEW FormData, not the consumed one' );
      expect( retry.text, contains( 'name="file"; filename="asr-reply-123.ogg"' ) );
      expect( retry.text, contains( 'OGG-AUDIO-BYTES' ), reason: 'the retried body carries the audio again' );
      expect( retry.bytes.length, first.bytes.length );
    } );
  } );

  group( 'recording disposal — B-J3, with a denominator', () {
    // §3.2's seven wire-outcome rows, plus the stream nobody listens to (CB3).
    // For each: askSpoken leaves the recording alone (positive control — so
    // the delete really is discardPendingUpload's doing), and
    // discardPendingUpload then leaves no file.
    final outcomes = <String, _Responder>{
      'non-200'                          : ( _ ) => _jsonError( 503, { 'detail': 'busy' } ),
      'body closes before any line'      : ( _ ) => _chunked( [] ),
      'transcript line then ask line'    : ( _ ) => _chunked( [ _bytes( _transcriptLine + _askLine ) ] ),
      'error line'                       : ( _ ) => _chunked( [ _bytes( _transcriptLine + _errorLine ) ] ),
      'body closes after the transcript' : ( _ ) => _chunked( [ _bytes( _transcriptLine ) ] ),
      'malformed line'                   : ( _ ) => _chunked( [ _bytes( '${_transcriptLine}garbage\n' ) ] ),
      'network error mid-body'           : ( _ ) => _breaksAfter( _transcriptLine ),
    };
    test( 'the denominator is §3.2\'s seven wire-outcome rows', () {
      expect( outcomes, hasLength( 7 ) );
    } );

    late _MockRecorder recorder;
    late AsrService    asr;
    late String        recordedPath;

    setUpAll( () {
      registerFallbackValue( const RecordConfig() );
      registerFallbackValue( AudioEncoder.wav );
    } );

    setUp( () {
      recorder = _MockRecorder();
      asr      = AsrService( dio: _MockDio(), recorder: recorder, tempDirProvider: () async => tempDir );
      when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
      when( () => recorder.isEncoderSupported( any() ) ).thenAnswer( ( _ ) async => true );
      when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( inv ) async {
        recordedPath = inv.namedArguments[ #path ] as String;
        File( recordedPath ).writeAsBytesSync( utf8.encode( 'WAV-BYTES' ) );
      } );
      when( () => recorder.stop() ).thenAnswer( ( _ ) async => recordedPath );
    } );

    Future<String> record() async {
      await asr.startRecording();
      final path = await asr.stopToFile();
      expect( path, recordedPath );
      expect( asr.isCapturing, isFalse, reason: 'stopToFile clears the active capture' );
      expect( File( path ).existsSync(), isTrue );
      return path;
    }

    for ( final entry in outcomes.entries ) {
      test( '${entry.key} → the stream leaves the file, discardPendingUpload removes it', () async {
        final path        = await record();
        final ( repo, _ ) = build( [ entry.value ] );
        await _drain( repo.askSpoken( path, 'ws-1' ) );
        expect( File( path ).existsSync(), isTrue, reason: 'askSpoken must not own the recording' );
        asr.discardPendingUpload( path );
        expect( File( path ).existsSync(), isFalse );
      } );
    }

    test( 'never-subscribed stream → discardPendingUpload still removes the file', () async {
      final path              = await record();
      final ( repo, adapter ) = build( [ outcomes.values.first ] );
      repo.askSpoken( path, 'ws-1' );                        // held, never listened to
      await Future<void>.delayed( Duration.zero );
      expect( adapter.sent, isEmpty );
      asr.discardPendingUpload( path );
      expect( File( path ).existsSync(), isFalse );
    } );

    test( 'two pending recordings: discarding one leaves the other (CC2 — two live streams)', () async {
      final first  = await record();
      final second = await record();
      expect( first, isNot( second ) );
      asr.discardPendingUpload( first );
      expect( File( first ).existsSync(), isFalse );
      expect( File( second ).existsSync(), isTrue, reason: 'the second stream is still uploading' );
      asr.discardPendingUpload( second );
      expect( File( second ).existsSync(), isFalse );
    } );

    test( 'only paths stopToFile handed out are deleted, and a second call is a no-op', () async {
      final stranger = File( '${tempDir.path}/not-a-recording.txt' )..writeAsStringSync( 'keep me' );
      asr.discardPendingUpload( stranger.path );
      expect( stranger.existsSync(), isTrue );

      final path = await record();
      asr.discardPendingUpload( path );
      File( path ).writeAsStringSync( 'a new file at the same path' );
      asr.discardPendingUpload( path );
      expect( File( path ).existsSync(), isTrue, reason: 'the path was already released' );
    } );
  } );

  group( 'ask-audio contract fixture CURRENCY, not presence (SB-fix)', () {
    // 🔴 Departure from rev 14, ruled by Mr. Radio 16:36–16:38 for rev 15 (John's
    // catch). The plan's row asserts `_capture.lupin_sha`, but the lupin fixture
    // carries `lupin_base_sha` and cannot hold its own commit sha. So the WHOLE
    // check is a byte comparison against lupin's fixture at a git ref:
    //   - default ref: lupin's working branch (below) — `main` is 1,715 commits
    //     behind and never sees the fixture;
    //   - `$LUPIN_FIXTURE_REF` overrides it. Until §A merges, the fixture lives
    //     only on `sam/ask-audio-door-a`, so this is RED on the default ref by
    //     design: run with LUPIN_FIXTURE_REF=sam/ask-audio-door-a until then.
    // Provenance, comment only: copied from lupin 36314bf7 (sam/ask-audio-door-a).
    // A missing lupin repo FAILS, never skips: a skip reads as green.
    const lupinPath       = 'src/tests/fixtures/ask_audio_ndjson_contract.json';
    const phonePath       = 'test/fixtures/asr/ask_audio_ndjson_contract.json';
    const defaultLupinRef = 'wip-v0.2.1-2026.08.29-cjflow-v2-followup';

    /// The lupin checkout: `$LUPIN_ROOT`, else the sibling of this repo's
    /// main checkout (works from a worktree too).
    String lupinRoot() {
      final looked = <String>[];
      final env    = Platform.environment[ 'LUPIN_ROOT' ];
      if ( env != null && env.isNotEmpty ) looked.add( env );
      final common = Process.runSync( 'git', [ 'rev-parse', '--path-format=absolute', '--git-common-dir' ] );
      if ( common.exitCode == 0 ) {
        final mainCheckout = File( ( common.stdout as String ).trim() ).parent;
        looked.add( '${mainCheckout.parent.path}/lupin' );
      }
      for ( final p in looked ) {
        if ( Directory( '$p/.git' ).existsSync() || File( '$p/.git' ).existsSync() ) return p;
      }
      fail( 'lupin repo not found — looked in: ${looked.join( ", " )}. '
            'Set LUPIN_ROOT to the lupin checkout. This test does not skip.' );
    }

    test( 'the phone copy is byte-identical to lupin\'s fixture at \$LUPIN_FIXTURE_REF (default: lupin working branch)', () {
      final env  = Platform.environment[ 'LUPIN_FIXTURE_REF' ];
      final ref  = ( env == null || env.isEmpty ) ? defaultLupinRef : env;
      final root = lupinRoot();
      final sha  = Process.runSync( 'git', [ '-C', root, 'rev-parse', '--verify', '$ref^{commit}' ] );
      final at   = sha.exitCode == 0 ? ( sha.stdout as String ).trim() : '<unresolved: ${( sha.stderr as String ).trim()}>';
      // Printed on every run, pass or fail, so a green says WHICH lupin it matched.
      // ignore: avoid_print
      print( 'fixture currency: lupin ref $ref @ $at' );
      final r    = Process.runSync( 'git', [ '-C', root, 'show', '$ref:$lupinPath' ], stdoutEncoding: null );
      if ( r.exitCode != 0 ) {
        fail( 'git show $ref:$lupinPath failed in $root (ref $ref @ $at): ${r.stderr}'
              'Until §A merges, run with LUPIN_FIXTURE_REF=sam/ask-audio-door-a.' );
      }
      expect( Uint8List.fromList( r.stdout as List<int> ), File( phonePath ).readAsBytesSync(),
          reason: 'lupin $ref @ $at has a different $lupinPath — re-copy it byte for byte' );
    } );
  } );
}
