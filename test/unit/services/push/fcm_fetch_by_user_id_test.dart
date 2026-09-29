/// Row 8ff78c69: the wake fetch must address the user by SYSTEM ID, not email.
/// Row 7cac3a17: and it fetches the unplayed LIST, not `/next`'s single item,
/// so a switched-off priority at the head of the queue cannot block the rest.
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
      'GET /api/notifications/$uid': ( _ ) => jsonBody( {
        'status': 'success',
        'notifications': [
          { 'id': 'n-1', 'message': 'hello' },
          { 'id': 'n-2', 'message': 'also hello' },
        ],
      } ),
    } );
    final items = await fetchUnplayedForAccessToken( dio: makeDio( adapter ), accessToken: token );

    expect( [ for ( final i in items ) i[ 'id' ] ], [ 'n-1', 'n-2' ] );
    expect( adapter.captured.single.path, '/api/notifications/$uid' );
    expect( adapter.captured.single.path, isNot( contains( '%40' ) ), reason: 'no email in the path' );
    expect( adapter.captured.single.headers[ 'Authorization' ], 'Bearer $token' );
  } );

  test( 'it asks for UNPLAYED items only — a played item must never be re-shown', () async {
    final adapter = StubAdapter( {
      'GET /api/notifications/$uid': ( _ ) => jsonBody( { 'status': 'success', 'notifications': [] } ),
    } );
    await fetchUnplayedForAccessToken( dio: makeDio( adapter ), accessToken: token );

    final q = adapter.captured.single.queryParameters;
    expect( q[ 'include_played' ], false );
    expect( q[ 'limit' ], kFcmWakeUnplayedLimit );
  } );

  test( 'nothing unplayed ⇒ an EMPTY list, never null', () async {
    final adapter = StubAdapter( {
      'GET /api/notifications/$uid': ( _ ) => jsonBody( { 'status': 'success', 'notifications': [] } ),
    } );
    expect( await fetchUnplayedForAccessToken( dio: makeDio( adapter ), accessToken: token ), isEmpty );
  } );

  test( 'a malformed body is an empty list, not a crash in a background isolate', () async {
    final adapter = StubAdapter( {
      'GET /api/notifications/$uid': ( _ ) => jsonBody( { 'status': 'success' } ),
    } );
    expect( await fetchUnplayedForAccessToken( dio: makeDio( adapter ), accessToken: token ), isEmpty );
  } );
}
