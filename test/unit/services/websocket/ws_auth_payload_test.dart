/// AC-S5.5 (F-S6-1) — the WS `auth_request` payload carries
/// `client_type: "mobile"`, fixture-pinned against the §3.1 contract
/// (S6 §3.0 / S5 §3.1: absent marker ⇒ web; the wake trigger fires on
/// "no live MOBILE WS", so the marker is what stops a desktop browser
/// suppressing the phone's wake).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/websocket/websocket_service.dart';

void main() {
  group( 'WS auth_request payload (S5, AC-S5.5)', () {
    test( 'carries client_type: "mobile" alongside the legacy fields', () {
      final msg = WebSocketService.buildAuthRequestMessage(
        bearerToken : 'Bearer tok-123',
        sessionId   : 'wise penguin',
      );

      // Contract fixture — exact §3.1 shape, no drift in either direction.
      expect( msg, {
        'type'              : 'auth_request',
        'token'             : 'Bearer tok-123',
        'session_id'        : 'wise penguin',
        'subscribed_events' : [],
        'client_type'       : 'mobile',
      } );
    } );

    test( 'marker survives a null session id (first-connect shape)', () {
      final msg = WebSocketService.buildAuthRequestMessage(
        bearerToken : 'Bearer tok-123',
        sessionId   : null,
      );
      expect( msg[ 'client_type' ], 'mobile' );
      expect( msg[ 'type' ], 'auth_request' );
    } );
  } );
}
