/// F9 (row 8ff78c69): the wake path needs a refresh token, and nothing else.
///
/// The stored email was required alongside it from when the fetch was addressed
/// by email. f649d49 moved the fetch onto the JWT `sub` claim and the seam now
/// discards the email outright, but the gate kept demanding it — so a user with
/// a token and no stored email would have been told to sign in, silently, with
/// no fetch attempted.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/auth/secure_credential_store.dart';
import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test( 'a refresh token with NO stored email still yields credentials', () async {
    // The case the old gate turned into a false "sign in to see it".
    FlutterSecureStorage.setMockInitialValues( {
      'auth.dev.refresh_token': 'r-1',
    } );
    final creds = await readWakeCredentials(
      store: SecureCredentialStore(), contextId: 'dev' );

    expect( creds, isNotNull,
        reason: 'the token is all the fetch needs — the user IS logged in' );
    expect( creds!.refreshToken, 'r-1' );
    expect( creds.userEmail, '',
        reason: 'empty rather than absent: the fetch seam discards it anyway' );
  } );

  test( 'both stored: the email is still carried through', () async {
    FlutterSecureStorage.setMockInitialValues( {
      'auth.dev.refresh_token': 'r-1',
      'auth.dev.last_email'   : 'rick@test.com',
    } );
    final creds = await readWakeCredentials(
      store: SecureCredentialStore(), contextId: 'dev' );

    expect( creds!.refreshToken, 'r-1' );
    expect( creds.userEmail, 'rick@test.com' );
  } );

  test( 'NO refresh token is the real signed-out case, and still returns null', () async {
    // This is the one that must keep showing "Open Lupin and sign in", so
    // loosening the gate above must not have loosened this.
    FlutterSecureStorage.setMockInitialValues( {
      'auth.dev.last_email': 'rick@test.com',
    } );
    final creds = await readWakeCredentials(
      store: SecureCredentialStore(), contextId: 'dev' );

    expect( creds, isNull );
  } );

  test( 'credentials are per-context: another context\'s token is not ours', () async {
    FlutterSecureStorage.setMockInitialValues( {
      'auth.prod.refresh_token': 'r-prod',
    } );
    expect(
      await readWakeCredentials( store: SecureCredentialStore(), contextId: 'dev' ),
      isNull,
      reason: 'a token stored for prod must not sign the dev context in' );
  } );
}
