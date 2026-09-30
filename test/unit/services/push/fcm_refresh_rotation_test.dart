/// Row 8ff78c69: the background wake must SAVE the rotated refresh token.
///
/// Found on Rick's phone 2026-09-28: the server revokes a refresh token when it
/// is exchanged, and the wake handler threw the new one away, so the second
/// wake got 401 and the foreground's next refresh would have logged him out.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/auth/auth_repository.dart';
import 'package:lupin_mobile/services/auth/secure_credential_store.dart';
import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';

import '../../_helpers/stub_dio.dart';

/// The server's REAL response shape (lupin `auth.py`, RefreshResponse): the
/// tokens are NESTED. A flat mock is what let the first cut of this fix pass
/// its tests and still fail on the emulator.
Map<String, dynamic> envelope( String access, String refresh ) => {
  'message' : 'Token refreshed',
  'tokens'  : { 'access_token': access, 'refresh_token': refresh, 'token_type': 'bearer' },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureCredentialStore store;

  setUp( () {
    FlutterSecureStorage.setMockInitialValues( { 'auth.dev.refresh_token': 'old-refresh' } );
    store = SecureCredentialStore();
  } );

  test( 'the rotated refresh token is saved, and the access token returned', () async {
    final adapter = StubAdapter( {
      'POST /auth/refresh': ( _ ) => jsonBody( envelope( 'new-access', 'new-refresh' ) ),
    } );
    final access = await exchangeRefreshAndPersist(
      dio: makeDio( adapter ), store: store, contextId: 'dev', refreshToken: 'old-refresh' );

    expect( access, 'new-access' );
    expect( await store.readRefreshToken( 'dev' ), 'new-refresh',
        reason: 'the old token is revoked server-side; keeping it logs the user out' );
    expect( adapter.captured.single.data, { 'refresh_token': 'old-refresh' } );
  } );

  test( 'a second wake presents the ROTATED token, not the revoked one', () async {
    var n = 0;
    final seen = <Object?>[];
    final adapter = StubAdapter( {
      'POST /auth/refresh': ( o ) {
        seen.add( ( o.data as Map )[ 'refresh_token' ] );
        n++;
        return jsonBody( envelope( 'a$n', 'r$n' ) );
      },
    } );
    final dio = makeDio( adapter );
    for ( var i = 0; i < 2; i++ ) {
      final current = await store.readRefreshToken( 'dev' );
      await exchangeRefreshAndPersist( dio: dio, store: store, contextId: 'dev', refreshToken: current! );
    }
    expect( seen, [ 'old-refresh', 'r1' ] );
  } );

  test( 'a flat body (tokens NOT nested) is refused, and the stored token is left alone', () async {
    final adapter = StubAdapter( {
      'POST /auth/refresh': ( _ ) => jsonBody( { 'access_token': 'x', 'refresh_token': 'y' } ),
    } );
    await expectLater(
      exchangeRefreshAndPersist( dio: makeDio( adapter ), store: store, contextId: 'dev', refreshToken: 'old-refresh' ),
      throwsA( anything ) );
    expect( await store.readRefreshToken( 'dev' ), 'old-refresh' );
  } );

  test( 'a failed exchange throws and leaves the stored token alone', () async {
    final adapter = StubAdapter( {
      'POST /auth/refresh': ( _ ) => jsonBody( { 'detail': 'revoked' }, status: 401 ),
    } );
    await expectLater(
      exchangeRefreshAndPersist( dio: makeDio( adapter ), store: store, contextId: 'dev', refreshToken: 'old-refresh' ),
      throwsA( anything ) );
    expect( await store.readRefreshToken( 'dev' ), 'old-refresh' );
  } );

  group( 'F4 — losing the rotation race is not a logout (row 8ff78c69)', () {
    // The stored refresh token has TWO writers: this background isolate and the
    // foreground AuthInterceptor. The server revokes on every exchange, so when
    // a wake lands while the app is backgrounded-but-alive, both can present the
    // same token and the loser gets a 401 on a token that was valid when it read
    // it. That used to read as a dead session.

    test( 'a 401 on a token the foreground already rotated: re-read, retry once, succeed',
        () async {
      final presented = <Object?>[];
      final adapter = StubAdapter( {
        'POST /auth/refresh': ( o ) {
          final tok = ( o.data as Map )[ 'refresh_token' ];
          presented.add( tok );
          // 'old-refresh' is the copy this isolate read before the foreground
          // won the race and wrote 'foreground-wrote-this'.
          if ( tok == 'old-refresh' ) return jsonBody( { 'detail': 'revoked' }, status: 401 );
          return jsonBody( envelope( 'access-2', 'refresh-2' ) );
        },
      } );
      // The winner's write lands in the store while we hold the stale copy.
      await store.writeRefreshToken( 'dev', 'foreground-wrote-this' );

      final access = await exchangeRefreshAndPersist(
        dio: makeDio( adapter ), store: store, contextId: 'dev',
        refreshToken: 'old-refresh' );

      expect( access, 'access-2', reason: 'the wake still completes' );
      expect( presented, [ 'old-refresh', 'foreground-wrote-this' ],
          reason: 'exactly one retry, with the token the winner left behind' );
      expect( await store.readRefreshToken( 'dev' ), 'refresh-2' );
    } );

    test( 'a 401 on a token the store STILL agrees with is a real dead session', () async {
      // Nothing rotated underneath us, so there is nothing to retry with and a
      // retry loop would just be a log-out with extra steps.
      var calls = 0;
      final adapter = StubAdapter( {
        'POST /auth/refresh': ( _ ) { calls++; return jsonBody( { 'detail': 'revoked' }, status: 401 ); },
      } );
      await expectLater(
        exchangeRefreshAndPersist(
          dio: makeDio( adapter ), store: store, contextId: 'dev',
          refreshToken: 'old-refresh' ),
        throwsA( isA<AuthException>() ) );
      expect( calls, 1, reason: 'no retry when the store has nothing newer' );
      expect( await store.readRefreshToken( 'dev' ), 'old-refresh' );
    } );

    test( 'a NON-401 failure is never retried', () async {
      var calls = 0;
      final adapter = StubAdapter( {
        'POST /auth/refresh': ( _ ) { calls++; return jsonBody( { 'detail': 'boom' }, status: 500 ); },
      } );
      await store.writeRefreshToken( 'dev', 'something-else' );
      await expectLater(
        exchangeRefreshAndPersist(
          dio: makeDio( adapter ), store: store, contextId: 'dev',
          refreshToken: 'old-refresh' ),
        throwsA( isA<AuthException>() ) );
      expect( calls, 1, reason: 'a 500 is not a rotation race' );
    } );

    test( 'the retry is at most ONE: a 401 on the fresh token too still throws', () async {
      var calls = 0;
      final adapter = StubAdapter( {
        'POST /auth/refresh': ( _ ) { calls++; return jsonBody( { 'detail': 'revoked' }, status: 401 ); },
      } );
      await store.writeRefreshToken( 'dev', 'also-revoked' );
      await expectLater(
        exchangeRefreshAndPersist(
          dio: makeDio( adapter ), store: store, contextId: 'dev',
          refreshToken: 'old-refresh' ),
        throwsA( isA<AuthException>() ) );
      expect( calls, 2, reason: 'one attempt, one retry, then give up' );
    } );
  } );

  group( 'F5 — a failed store write must not silently cost the account (row 8ff78c69)', () {
    // The exchange has already revoked the old token by the time the write runs,
    // so between those two lines the only usable refresh token is a local
    // variable. The likeliest cause of a failure there is the very state a Doze
    // wake runs in: a device booted but never unlocked, keystore not yet up.

    test( 'a TRANSIENT write failure is retried, and the token does land', () async {
      var attempts = 0;
      final store = _FlakyStore( failures: 2, onWrite: () => attempts++ );
      final adapter = StubAdapter( {
        'POST /auth/refresh': ( _ ) => jsonBody( envelope( 'acc', 'rotated' ) ),
      } );
      final logs = <String>[];

      final access = await exchangeRefreshAndPersist(
        dio: makeDio( adapter ), store: store, contextId: 'dev',
        refreshToken: 'old-refresh', logSink: logs.add );

      expect( access, 'acc' );
      expect( attempts, 3, reason: 'two failures, then the write that sticks' );
      expect( store.stored, 'rotated' );
      expect( logs.any( ( l ) => l.contains( 'saved on attempt 3' ) ), isTrue );
      expect( logs.any( ( l ) => l.contains( kFcmRefreshWriteLostMarker ) ), isFalse );
    } );

    test( 'a PERMANENT write failure keeps the wake and says so unmistakably', () async {
      final store = _FlakyStore( failures: 99, onWrite: () {} );
      final adapter = StubAdapter( {
        'POST /auth/refresh': ( _ ) => jsonBody( envelope( 'acc', 'rotated' ) ),
      } );
      final logs = <String>[];

      // It must NOT throw: the old token is already revoked, so failing the wake
      // as well would cost the notification and save nothing.
      final access = await exchangeRefreshAndPersist(
        dio: makeDio( adapter ), store: store, contextId: 'dev',
        refreshToken: 'old-refresh', logSink: logs.add );

      expect( access, 'acc', reason: 'the user still gets this notification' );
      expect( logs.any( ( l ) => l.contains( kFcmRefreshWriteLostMarker ) ), isTrue,
          reason: 'the only warning anyone gets before the forced re-login' );
      expect( logs.where( ( l ) => l.contains( 'retrying' ) ).length,
          kFcmRefreshWriteAttempts - 1 );
    } );
  } );
}

/// A store whose writes fail the first [failures] times. Reads come from
/// whatever a successful write last accepted.
class _FlakyStore extends SecureCredentialStore {
  final int failures;
  final void Function() onWrite;
  int  _seen = 0;
  String? stored;

  _FlakyStore( { required this.failures, required this.onWrite } );

  @override
  Future<void> writeRefreshToken( String contextId, String token ) async {
    onWrite();
    _seen++;
    if ( _seen <= failures ) throw Exception( 'keystore unavailable (device not unlocked)' );
    stored = token;
  }

  @override
  Future<String?> readRefreshToken( String contextId ) async => stored;
}
