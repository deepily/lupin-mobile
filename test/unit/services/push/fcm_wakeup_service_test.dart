/// S5 token-lifecycle tests — AC-S5.1 + AC-S5.2 (incl. the F-S6-S2-1(b)
/// WS-reconnect re-registration extension). The §3.1 contract payloads are
/// asserted FIELD-EXACT (OSQ-6 ratified shape, POST-unregister amendment).
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/push/fcm_wakeup_service.dart';

class _MockDio extends Mock implements Dio {}

class _FakeTokenSource implements FcmTokenSource {
  String? token;
  final StreamController<String> refreshCtrl = StreamController<String>.broadcast();

  _FakeTokenSource( this.token );

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => refreshCtrl.stream;
}

void main() {
  group( 'FcmWakeupService (S5 token lifecycle)', () {
    late _MockDio        dio;
    late _FakeTokenSource tokens;
    late FcmWakeupService service;
    late List<String>    logs;

    Response<Map<String, dynamic>> ok( String path ) => Response(
      requestOptions : RequestOptions( path: path ),
      data           : { 'status': 'ok' },
      statusCode     : 200,
    );

    setUp( () {
      dio    = _MockDio();
      tokens = _FakeTokenSource( 'tok-1' );
      logs   = [];
      service = FcmWakeupService(
        tokenSource : tokens,
        dio         : dio,
        log         : logs.add,
      );
      when( () => dio.post<Map<String, dynamic>>( any(), data: any( named: 'data' ) ) )
          .thenAnswer( ( inv ) async =>
              ok( inv.positionalArguments.first as String ) );
    } );

    tearDown( () async {
      await service.dispose();
      await tokens.refreshCtrl.close();
    } );

    test( 'AC-S5.1 — token obtained → registration POST with the §3.1-declared payload', () async {
      await service.onAuthenticated( 'rick@test.com' );

      final captured = verify( () => dio.post<Map<String, dynamic>>(
        captureAny(),
        data: captureAny( named: 'data' ),
      ) ).captured;

      expect( captured[ 0 ], FcmWakeupService.registerPath );
      expect( captured[ 0 ], '/api/fcm/register-token' );
      // FIELD-EXACT §3.1 body: { token, platform: "android", user_email }.
      expect( captured[ 1 ], {
        'token'      : 'tok-1',
        'platform'   : 'android',
        'user_email' : 'rick@test.com',
      } );
    } );

    test( 'AC-S5.1 — null token: registration skipped, no POST', () async {
      tokens.token = null;
      await service.onAuthenticated( 'rick@test.com' );
      verifyNever( () => dio.post<Map<String, dynamic>>( any(),
          data: any( named: 'data' ) ) );
    } );

    test( 'AC-S5.2 — onTokenRefresh re-registers with the ROTATED token', () async {
      await service.onAuthenticated( 'rick@test.com' );

      tokens.refreshCtrl.add( 'tok-2' );
      await Future<void>.delayed( Duration.zero );

      final bodies = verify( () => dio.post<Map<String, dynamic>>(
        any( that: equals( FcmWakeupService.registerPath ) ),
        data: captureAny( named: 'data' ),
      ) ).captured;
      expect( bodies, hasLength( 2 ) );
      expect( ( bodies[ 1 ] as Map )[ 'token' ], 'tok-2' );
    } );

    test( 'AC-S5.2 — logout unregisters via POST /api/fcm/unregister-token { token }', () async {
      await service.onAuthenticated( 'rick@test.com' );
      await service.onLoggedOut();

      final captured = verify( () => dio.post<Map<String, dynamic>>(
        any( that: equals( FcmWakeupService.unregisterPath ) ),
        data: captureAny( named: 'data' ),
      ) ).captured;
      expect( captured.single, { 'token': 'tok-1' } );
    } );

    test( 'AC-S5.2 ext (F-S6-S2-1(b)) — WS reconnect fires a REPEAT registration POST (idempotent upsert)', () async {
      await service.onAuthenticated( 'rick@test.com' );
      await service.onWsReconnected();
      await service.onWsReconnected();   // every reconnect — cheap + safe

      final bodies = verify( () => dio.post<Map<String, dynamic>>(
        any( that: equals( FcmWakeupService.registerPath ) ),
        data: captureAny( named: 'data' ),
      ) ).captured;
      expect( bodies, hasLength( 3 ), reason: 'login + 2 reconnects' );
      expect( bodies, everyElement( equals( bodies.first ) ),
          reason: 'identical upsert payload each time' );
    } );

    test( 'WS reconnect before any login: no POST (nothing to upsert)', () async {
      await service.onWsReconnected();
      verifyNever( () => dio.post<Map<String, dynamic>>( any(),
          data: any( named: 'data' ) ) );
    } );

    test( 'register failure is non-fatal and logged (next writer retries)', () async {
      when( () => dio.post<Map<String, dynamic>>( any(), data: any( named: 'data' ) ) )
          .thenThrow( DioException(
            requestOptions: RequestOptions( path: FcmWakeupService.registerPath ),
            message: 'boom',
          ) );
      await service.onAuthenticated( 'rick@test.com' );   // must not throw
      expect( logs.any( ( l ) => l.contains( 'register failed' ) ), isTrue );
    } );
  } );
}
