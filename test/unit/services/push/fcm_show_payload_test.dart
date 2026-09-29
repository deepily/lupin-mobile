import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';
import 'package:lupin_mobile/services/push/notification_tap_payload.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}
class _FakeDetails extends Fake implements NotificationDetails {}

/// Row d9bc6f6c — the PRODUCTION post, not the seam.
///
/// 🔴 WHY THIS FILE EXISTS, AND IT IS NOT REDUNDANT WITH `fcm_wake_chain_test`.
/// That file proves the chain hands a payload to its `showNotification` seam — by
/// supplying the seam itself. The production seam lives in
/// `buildBackgroundWakeChain`, and it is what actually talks to the plugin.
///
/// Measured during this row: `payload:` was deleted from that production call as
/// a deliberate mutation. The ENTIRE push suite stayed green and `flutter analyze`
/// reported nothing — every unit test above still passed while the shipped app
/// posted notifications that could route nowhere, which is precisely the bug being
/// fixed. That is the uninjected-seam shape this repo has been bitten by before
/// (bug 9adff476), and it is why the call was extracted into
/// [showWakeNotification] rather than left inline where nothing could reach it.
void main() {
  setUpAll( () => registerFallbackValue( _FakeDetails() ) );

  late _MockPlugin plugin;

  setUp( () {
    plugin = _MockPlugin();
    when( () => plugin.show( any(), any(), any(), any(),
        payload: any( named: 'payload' ) ) ).thenAnswer( ( _ ) async {} );
  } );

  /// What the plugin was actually handed.
  ({ String? title, String? body, String? payload }) captured() {
    final call = verify( () => plugin.show(
      any(), captureAny(), captureAny(), any(),
      payload: captureAny( named: 'payload' ) ) ).captured;
    return (
      title   : call[ 0 ] as String?,
      body    : call[ 1 ] as String?,
      payload : call[ 2 ] as String?,
    );
  }

  /// The NotificationDetails the plugin was actually handed — Maya's `captured()`
  /// passes `any()` there, so nothing pinned it.
  NotificationDetails capturedDetails() {
    final call = verify( () => plugin.show(
      any(), any(), any(), captureAny(),
      payload: any( named: 'payload' ) ) ).captured;
    return call.single as NotificationDetails;
  }

  test( 'C4 — the production post lands on the v2 channel at DEFAULT importance',
      () async {
    // 🔴 ASSERTED ON WHAT THE PLUGIN RECEIVES, NOT ON THE GETTER (Chloé's C4).
    // fcm_wake_channel_test checks that wakeNotificationDetails() returns the v2
    // id at default importance — true, and not the same claim. Nothing there
    // required the SHIPPED post to use that getter, so pointing
    // showWakeNotification at any other NotificationDetails would have left both
    // files green while Rick's phone went back to a 3am heads-up banner on the old
    // channel. This is the same uninjected-seam shape the header of this file
    // describes, one argument to the right of the payload it was written for.
    await showWakeNotification( plugin, '🌻 Maya', 'Build finished green.', null );

    final android = capturedDetails().android!;
    expect( android.channelId, 'lupin_fcm_wake_v2',
        reason: 'the v2 bump is what carries the importance change to existing installs' );
    expect( android.importance, Importance.defaultImportance,
        reason: 'shade, not a banner over whatever is on screen' );
    expect( android.priority, Priority.defaultPriority );
    expect( android.channelName, 'Lupin background notifications',
        reason: 'the name the user looks for after the id changes underneath them' );
  } );

  test( 'the production post forwards its payload to the plugin VERBATIM', () async {
    final payload = const NotificationTapPayload(
      notificationId : 'n-77',
      senderId       : 'claude.code@lupin-mobile.deepily.ai#a1b2c3d4',
    ).encode();

    await showWakeNotification( plugin, '🌻 Maya', 'Build finished green.', payload );

    final c = captured();
    expect( c.payload, payload,
        reason: 'the string the main isolate will read back off the launch intent' );

    // And it is still decodable after the round trip through the call.
    final decoded = NotificationTapPayload.decode( c.payload );
    expect( decoded?.notificationId, 'n-77' );
    expect( decoded?.senderId, 'claude.code@lupin-mobile.deepily.ai#a1b2c3d4' );
  } );

  test( 'the title and body are forwarded unchanged', () async {
    await showWakeNotification( plugin, '🌻 Maya', 'Build finished green.', null );

    final c = captured();
    expect( c.title, '🌻 Maya' );
    expect( c.body, 'Build finished green.' );
  } );

  test( 'a null payload is forwarded as null, not as an empty string', () async {
    // The fallback notifications. `''` would be indistinguishable from the
    // plugin's own default, which is exactly what every pre-fix notification
    // carried — so the distinction is worth keeping at this boundary.
    await showWakeNotification( plugin, 'Lupin', 'New activity.', null );

    expect( captured().payload, isNull );
  } );

  test( 'NEGATIVE CONTROL: this test can SEE a dropped payload', () async {
    // Proof the assertions above are not vacuous. If `show` were called without
    // the named argument at all, the stub above would not match and `verify`
    // would find no call — so a mutation that drops `payload:` cannot pass here
    // the way it passed the whole suite before this file existed.
    await showWakeNotification( plugin, 'Lupin', 'New activity.', 'p' );

    expect( captured().payload, 'p' );
    verifyNever( () => plugin.show( any(), any(), any(), any() ) );
  } );
}
