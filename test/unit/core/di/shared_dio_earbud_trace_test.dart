/// The service locator puts one earbud trace uploader on the logger, however often it starts.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/audio/lupin_media_handler.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';
import 'package:lupin_mobile/services/diagnostics/earbud_trace_uploader.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch( RequestOptions options, Stream<Uint8List>? body, Future<void>? cancel ) async {
    requests.add( options.uri );
    return ResponseBody.fromString( '{}', 200 );
  }

  @override
  void close( { bool force = false } ) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shippedJson = File( 'assets/config/server-contexts.json' ).readAsStringSync();

  late ServerContextService svc;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler( 'flutter/assets', ( message ) async {
        final key = const StringCodec().decodeMessage( message );
        return key == 'assets/config/server-contexts.json'
          ? const StringCodec().encodeMessage( shippedJson )
          : null;
      } );
    Logger.resetForTesting();
    await ServiceLocator.reset();
    svc = await ServerContextService.load( await SharedPreferences.getInstance() );
  } );

  tearDown( () async {
    await ServiceLocator.reset();
    Logger.resetForTesting();
  } );

  /// Registers the shared Dio and swaps the new uploader's network for a recording stub.
  _Adapter register() {
    ServiceLocator.registerSharedDio( svc );
    final adapter = _Adapter();
    EarbudTraceUploader.installed!.dio.httpClientAdapter = adapter;
    return adapter;
  }

  Future<void> sendLine() async {
    Logger.info( 'click: button=media', tag: LupinMediaHandler.logTag );
    await Future<void>.delayed( const Duration( milliseconds: 20 ) );
  }

  test( 'registering the shared Dio installs a trace uploader that sends a line to /health', () async {
    final adapter = register();
    await sendLine();

    expect( adapter.requests.single.path, '/health' );
    expect( adapter.requests.single.queryParameters, { 'earbud_trace': 'click: button=media' } );
  } );

  test( 'a reset and a second registration leave one uploader, so a line is sent once', () async {
    final first = register();
    await ServiceLocator.reset();
    final second = register();
    await sendLine();

    expect( first.requests, isEmpty, reason: 'the earlier uploader left the logger' );
    expect( second.requests, hasLength( 1 ) );
  } );

  test( 'the uploader follows a server switch and is not the shared Dio', () async {
    final adapter = register();
    await svc.setActive( 'lan-dev' );
    await sendLine();

    expect( adapter.requests.single.host, '192.168.1.21' );
    expect( EarbudTraceUploader.installed!.dio, isNot( same( ServiceLocator.get<Dio>() ) ) );
  } );
}
