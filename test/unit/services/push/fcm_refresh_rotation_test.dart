/// Row 8ff78c69: the background wake must SAVE the rotated refresh token.
///
/// Found on Rick's phone 2026-09-28: the server revokes a refresh token when it
/// is exchanged, and the wake handler threw the new one away, so the second
/// wake got 401 and the foreground's next refresh would have logged him out.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/auth/secure_credential_store.dart';
import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';

import '../../_helpers/stub_dio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureCredentialStore store;

  setUp( () {
    FlutterSecureStorage.setMockInitialValues( { 'auth.dev.refresh_token': 'old-refresh' } );
    store = SecureCredentialStore();
  } );

  test( 'the rotated refresh token is saved, and the access token returned', () async {
    final adapter = StubAdapter( {
      'POST /auth/refresh': ( _ ) => jsonBody( { 'access_token': 'new-access', 'refresh_token': 'new-refresh' } ),
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
        return jsonBody( { 'access_token': 'a$n', 'refresh_token': 'r$n' } );
      },
    } );
    final dio = makeDio( adapter );
    for ( var i = 0; i < 2; i++ ) {
      final current = await store.readRefreshToken( 'dev' );
      await exchangeRefreshAndPersist( dio: dio, store: store, contextId: 'dev', refreshToken: current! );
    }
    expect( seen, [ 'old-refresh', 'r1' ] );
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
}
