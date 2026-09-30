/// F8 (row 8ff78c69): a DENIED notification permission must leave a trace.
///
/// Denied, the whole wake chain still runs end to end and still logs
/// "[FcmWake] shown" while the shade stays empty — bit for bit the bug ba07dc8
/// was written to fix, only now with the fix installed. Nothing on the device
/// distinguishes it from a server problem, a revoked token or an APK built
/// without --fcm, so the one log line is the entire diagnostic.
///
/// `onWsAuthenticated` does the logging rather than
/// `requestNotificationPermission()`, so it sits behind the injectable seam and
/// this test can prove it without a platform channel.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/services/permissions/notification_permission.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockWs extends Mock implements WebSocketService {}

void main() {
  late _MockWs ws;
  late WsBlocDispatcher dispatcher;
  late List<String> logs;

  setUp( () {
    ws         = _MockWs();
    dispatcher = WsBlocDispatcher();
    logs       = [];
    // Already connected, so the hook does not touch connect() — this test is
    // about the permission arm, not the transport.
    when( () => ws.isConnected ).thenReturn( true );
  } );

  Future<void> run( { required bool granted } ) => onWsAuthenticated(
    dispatcher           : dispatcher,
    ws                   : ws,
    userId               : 'uuid-1',
    email                : 'rick@test.com',
    registerPush         : ( _ ) async {},
    requestNotifications : () async => granted,
    logSink              : logs.add,
  );

  test( 'a DENIED permission is logged under the grep-able marker', () async {
    await run( granted: false );
    expect( logs.where( ( l ) => l.contains( kNotificationPermissionDeniedMarker ) ).length, 1,
        reason: 'the only warning anyone gets that notifications cannot be posted' );
    expect( logs.single, contains( 'system settings' ),
        reason: 'and it says what to do about it' );
  } );

  test( 'a GRANTED permission logs nothing — the marker means something', () async {
    await run( granted: true );
    expect( logs, isEmpty,
        reason: 'a line on every login would make the denial line invisible' );
  } );

  test( 'a denial does not stop the login hook completing', () async {
    // The permission is the LAST step for a reason: a refused prompt must not
    // cost the user their session or their push registration.
    var registered = false;
    await onWsAuthenticated(
      dispatcher           : dispatcher,
      ws                   : ws,
      userId               : 'uuid-1',
      email                : 'rick@test.com',
      registerPush         : ( _ ) async => registered = true,
      requestNotifications : () async => false,
      logSink              : logs.add,
    );
    expect( registered, isTrue );
    expect( dispatcher.lastAuthenticatedEmail, 'rick@test.com' );
  } );

  // Row dfea49e7: a push-registration throw must not skip the permission prompt.
  test( 'a THROWING push registration still reaches the permission prompt', () async {
    var prompted = 0;
    await onWsAuthenticated(
      dispatcher           : dispatcher,
      ws                   : ws,
      userId               : 'uuid-1',
      email                : 'rick@test.com',
      registerPush         : ( _ ) async => throw StateError( 'no Play services' ),
      requestNotifications : () async { prompted++; return true; },
      logSink              : logs.add,
    );
    expect( prompted, 1, reason: 'else a fresh Android 13+ install never gets asked' );
    expect( logs.single, contains( 'push registration failed' ) );
    expect( logs.single, contains( 'no Play services' ) );
  } );

  test( 'a normal registration is unchanged: prompted once, nothing logged', () async {
    var prompted = 0;
    var pushed   = <String>[];
    await onWsAuthenticated(
      dispatcher           : dispatcher,
      ws                   : ws,
      userId               : 'uuid-1',
      email                : 'rick@test.com',
      registerPush         : ( e ) async => pushed.add( e ),
      requestNotifications : () async { prompted++; return true; },
      logSink              : logs.add,
    );
    expect( pushed, [ 'rick@test.com' ] );
    expect( prompted, 1 );
    expect( logs, isEmpty );
  } );
}
