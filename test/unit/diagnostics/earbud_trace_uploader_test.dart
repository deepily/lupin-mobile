/// The earbud trace uploader sends only trace lines and swallows upload failures.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/audio/lupin_media_handler.dart';
import 'package:lupin_mobile/services/diagnostics/earbud_trace_uploader.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <Uri>[];
  final bool fail;
  _Adapter( { this.fail = false } );

  @override
  Future<ResponseBody> fetch( RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel ) async {
    requests.add( options.uri );
    if ( fail ) throw DioException( requestOptions: options, type: DioExceptionType.connectionError );
    return ResponseBody.fromString( '{}', 200 );
  }

  @override
  void close( { bool force = false } ) {}
}

LogEntry _entry( String message, String? tag ) =>
    LogEntry( timestamp: DateTime( 2026 ), level: LogLevel.info, message: message, tag: tag );

void main() {
  test( 'an earbud trace line goes to /health as one query parameter', () async {
    final adapter = _Adapter();
    final up      = EarbudTraceUploader( Dio( BaseOptions( baseUrl: 'http://lupin.test' ) )..httpClientAdapter = adapter );

    up.write( _entry( 'click: button=media claimed=true', LupinMediaHandler.logTag ) );
    await Future<void>.delayed( const Duration( milliseconds: 20 ) );

    expect( adapter.requests.single.path, '/health' );
    expect( adapter.requests.single.queryParameters, { 'earbud_trace': 'click: button=media claimed=true' } );
  } );

  test( 'a line with another tag is not sent', () async {
    final adapter = _Adapter();
    final up      = EarbudTraceUploader( Dio( BaseOptions( baseUrl: 'http://lupin.test' ) )..httpClientAdapter = adapter );

    up.write( _entry( 'something else', 'StorageManager' ) );
    await Future<void>.delayed( const Duration( milliseconds: 20 ) );

    expect( adapter.requests, isEmpty );
  } );

  test( 'an upload that fails raises nothing', () async {
    final adapter = _Adapter( fail: true );
    final up      = EarbudTraceUploader( Dio( BaseOptions( baseUrl: 'http://lupin.test' ) )..httpClientAdapter = adapter );

    await runZonedGuarded( () async {
      up.write( _entry( 'gesture: single', LupinMediaHandler.logTag ) );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );
    }, ( e, s ) => fail( 'escaped: $e' ) );

    expect( adapter.requests, hasLength( 1 ) );
  } );

  group( 'install', () {
    setUp( Logger.resetForTesting );
    tearDown( Logger.resetForTesting );

    test( 'installing twice leaves one uploader, so a line is sent once', () async {
      final first  = _Adapter();
      final second = _Adapter();
      EarbudTraceUploader.install( baseUrl: 'http://one.test', dio: Dio()..httpClientAdapter = first );
      EarbudTraceUploader.install( baseUrl: 'http://two.test', dio: Dio()..httpClientAdapter = second );

      Logger.info( 'gesture: single', tag: LupinMediaHandler.logTag );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );

      expect( first.requests, isEmpty );
      expect( second.requests.single.host, 'two.test' );
    } );

    test( 'the uploader has its own Dio with no interceptors, so no auth refresh can start', () {
      final up = EarbudTraceUploader.install( baseUrl: 'http://one.test' );

      expect( up.dio.interceptors.whereType<InterceptorsWrapper>(), isEmpty );
      expect( up.dio.interceptors.length, 1, reason: 'Dio always holds its own import-conversion interceptor' );
      expect( up.dio.options.baseUrl, 'http://one.test' );
      expect( up.dio.options.connectTimeout, const Duration( seconds: 3 ) );
    } );

    test( 'switching server points later lines at the new host', () async {
      final adapter = _Adapter();
      final up      = EarbudTraceUploader.install( baseUrl: 'http://one.test', dio: Dio()..httpClientAdapter = adapter );
      up.baseUrl = 'http://two.test';

      Logger.info( 'click', tag: LupinMediaHandler.logTag );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );

      expect( adapter.requests.single.host, 'two.test' );
    } );
  } );
}
