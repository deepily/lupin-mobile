/// Row 8ff78c69: the wake fetch must address the user by SYSTEM ID, not email.
///
/// Emulator logcat 2026-09-28 17:02: `fetched 0 — nothing undelivered` on three
/// wakes in a row while notifications were queued, because the server's /next
/// matches the path against each item's UUID `user_id`.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';

import '../../_helpers/stub_dio.dart';

String fakeJwt( Map<String, dynamic> claims ) {
  String seg( Object o ) => base64Url.encode( utf8.encode( jsonEncode( o ) ) ).replaceAll( '=', '' );
  return '${seg( { 'alg': 'HS256', 'typ': 'JWT' } )}.${seg( claims )}.sig';
}

void main() {
  const uid   = '0cf47e2d-d5a1-4cd4-addf-79810fd32b15';
  final token = fakeJwt( { 'sub': uid, 'email': 'rick@x.y', 'roles': [ 'user' ] } );

  test( 'the user id is the token\'s sub claim', () {
    expect( userIdFromAccessToken( token ), uid );
  } );

  test( 'a token with no sub, or not a JWT, is refused', () {
    expect( () => userIdFromAccessToken( fakeJwt( { 'email': 'rick@x.y' } ) ), throwsFormatException );
    expect( () => userIdFromAccessToken( 'not-a-jwt' ), throwsFormatException );
  } );

  test( 'the fetch is addressed by user id, never by email', () async {
    final adapter = StubAdapter( {
      'GET /api/notifications/$uid/next': ( _ ) => jsonBody( {
        'status': 'success', 'notification': { 'id': 'n-1', 'message': 'hello' } } ),
    } );
    final item = await fetchNextForAccessToken( dio: makeDio( adapter ), accessToken: token );

    expect( item?[ 'id' ], 'n-1' );
    expect( adapter.captured.single.path, '/api/notifications/$uid/next' );
    expect( adapter.captured.single.path, isNot( contains( '%40' ) ), reason: 'no email in the path' );
    expect( adapter.captured.single.headers[ 'Authorization' ], 'Bearer $token' );
  } );

  test( 'no notification ⇒ null', () async {
    final adapter = StubAdapter( {
      'GET /api/notifications/$uid/next': ( _ ) => jsonBody( { 'status': 'success', 'notification': null } ),
    } );
    expect( await fetchNextForAccessToken( dio: makeDio( adapter ), accessToken: token ), isNull );
  } );
}
