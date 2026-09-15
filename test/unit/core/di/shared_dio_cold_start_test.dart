/// Fold-later from the 597c5dc review (row 8d9b2a0c): the shared Dio followed
/// a SWITCH but nothing put the SAVED server on it at start-up — it relied on
/// HttpService's constructor, built later in `_initializeServices`, to stamp
/// AppConstants onto it. AuthRepository and AuthInterceptor are handed the Dio
/// BEFORE that, so these tests drive the cold-start window directly: the
/// locator's real Dio registration, the real AuthRepository, and no
/// HttpService at all.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';

import '../../_helpers/stub_dio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shippedJson = File( "assets/config/server-contexts.json" ).readAsStringSync();

  /// A cold start with [saved] as the previously-chosen server: fresh prefs,
  /// the shipped JSON, the locator's Dio registration. NO HttpService.
  Future<ServerContextService> coldStart( String? saved ) async {
    SharedPreferences.setMockInitialValues(
      saved == null ? {} : { "active_server_context": saved },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler( "flutter/assets", ( message ) async {
        final key = const StringCodec().decodeMessage( message );
        return key == "assets/config/server-contexts.json"
          ? const StringCodec().encodeMessage( shippedJson )
          : null;
      } );
    await ServiceLocator.reset();
    final svc = await ServerContextService.load( await SharedPreferences.getInstance() );
    ServiceLocator.registerSharedDio( svc );
    return svc;
  }

  tearDown( () async => ServiceLocator.reset() );

  test( "cold start with LAN DEV saved: the shared Dio is on the LAN host before HttpService exists", () async {
    await coldStart( "lan-dev" );
    expect( ServiceLocator.get<Dio>().options.baseUrl, "http://192.168.1.21:7999" );
  } );

  test( "cold start with nothing saved: the shared Dio is on the JSON's default", () async {
    await coldStart( null );
    expect( ServiceLocator.get<Dio>().options.baseUrl, "http://10.0.2.2:7999" );
  } );

  test( "cold start with LAN TEST saved: a sign-in posted before HttpService reaches the LAN host", () async {
    await coldStart( "lan-test" );
    final dio     = ServiceLocator.get<Dio>();
    final adapter = StubAdapter( {
      "POST /auth/login": ( _ ) => jsonBody( { "detail": "bad credentials" }, status: 401 ),
    } );
    dio.httpClientAdapter = adapter;

    // AuthRepository is registered BEFORE HttpService and posts a relative
    // path, so this is the request the cold-start window can actually make.
    await expectLater(
      AuthRepository( dio ).login( "u@x.y", "pw" ),
      throwsA( isA<AuthException>() ),
    );

    expect( adapter.captured, hasLength( 1 ) );
    expect( adapter.captured.single.uri.toString(), "http://192.168.1.21:8000/auth/login" );
  } );
}
