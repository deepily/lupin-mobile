import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';
import 'package:lupin_mobile/services/network/http_service.dart';

import '../../_helpers/stub_dio.dart';

/// Review blocker on 597c5dc: the shared Dio's baseUrl was stamped once at
/// start-up, so after picking LAN DEV sign-in still went to 10.0.2.2 while
/// WebSocket code (reading AppConstants) followed the new host. These tests
/// drive the PRODUCTION Dio registration and the real AuthRepository.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shippedJson = File( "assets/config/server-contexts.json" ).readAsStringSync();

  late ServerContextService svc;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler( "flutter/assets", ( message ) async {
        final key = const StringCodec().decodeMessage( message );
        return key == "assets/config/server-contexts.json"
          ? const StringCodec().encodeMessage( shippedJson )
          : null;
      } );
    await ServiceLocator.reset();
    svc = await ServerContextService.load( await SharedPreferences.getInstance() );
    ServiceLocator.registerSharedDio( svc );
    // Start-up configuration, exactly as the locator does it (stamps baseUrl once).
    HttpService( ServiceLocator.get<Dio>() );
  } );

  tearDown( () async => ServiceLocator.reset() );

  test( "the GetIt Dio starts on DEV and follows a switch to LAN DEV, then back", () async {
    expect( ServiceLocator.get<Dio>().options.baseUrl, "http://10.0.2.2:7999" );

    await svc.setActive( "lan-dev" );
    expect( ServiceLocator.get<Dio>().options.baseUrl, "http://192.168.1.21:7999" );
    expect( AppConstants.wsBaseUrl, "ws://192.168.1.21:7999", reason: "HTTP and WebSocket agree" );

    await svc.setActive( "dev" );
    expect( ServiceLocator.get<Dio>().options.baseUrl, "http://10.0.2.2:7999" );
  } );

  test( "after switching to LAN DEV, a login request goes to the LAN host", () async {
    final dio     = ServiceLocator.get<Dio>();
    final adapter = StubAdapter( {
      "POST /auth/login": ( _ ) => jsonBody( { "detail": "bad credentials" }, status: 401 ),
    } );
    dio.httpClientAdapter = adapter;

    await svc.setActive( "lan-dev" );
    await expectLater(
      AuthRepository( dio ).login( "u@x.y", "pw" ),
      throwsA( isA<AuthException>() ),
    );

    expect( adapter.captured, hasLength( 1 ) );
    expect( adapter.captured.single.uri.toString(), "http://192.168.1.21:7999/auth/login" );
  } );
}
