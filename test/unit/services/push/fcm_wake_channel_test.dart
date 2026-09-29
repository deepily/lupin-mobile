/// The v2 notification-channel bump (Tiffany's ruling 2026-09-28, row 1af7b3de).
///
/// Lowering `importance` in the code reached nobody who already had the app:
/// Android fixes a channel's importance when the channel is CREATED and ignores
/// every later change, so the original `lupin_fcm_wake` kept the high importance
/// it was first registered with and the 3am heads-up banner kept happening. A new
/// channel id is the only thing that makes the new importance apply to an
/// existing install — and the old channel has to be deleted, or the user is left
/// with two identically-named rows in their notification settings, one dead.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';

void main() {
  group( 'the wake notification channel', () {
    test( 'the id is v2, and is NOT the pre-v2 id', () async {
      // Asserted as the literal, not via the constant: the whole mechanism is
      // that this string CHANGED, so a test that reads it from the same constant
      // it is checking would pass on any value at all.
      expect( kFcmWakeChannelId, 'lupin_fcm_wake_v2' );
      expect( kFcmWakeChannelIdLegacy, 'lupin_fcm_wake' );
      expect( kFcmWakeChannelId, isNot( kFcmWakeChannelIdLegacy ),
          reason: 'same id ⇒ Android keeps the old importance ⇒ the fix reaches nobody' );
    } );

    test( 'wake notifications are posted on the v2 channel at DEFAULT importance',
        () async {
      final android = wakeNotificationDetails().android!;
      expect( android.channelId, 'lupin_fcm_wake_v2' );
      expect( android.importance, Importance.defaultImportance,
          reason: 'an overnight wake lands in the shade, not over the screen' );
      expect( android.priority, Priority.defaultPriority );
      // The user-visible name has to stay put: it is what they look for in
      // system settings after the id changes underneath them.
      expect( android.channelName, 'Lupin background notifications' );
    } );

    test( 'init deletes the LEGACY channel, and never the current one', () async {
      final deleted = <String>[];
      await deleteLegacyWakeChannel( ( id ) async => deleted.add( id ) );

      expect( deleted, [ 'lupin_fcm_wake' ] );
      expect( deleted, isNot( contains( kFcmWakeChannelId ) ),
          reason: 'deleting the live channel would take the wake notifications with it' );
    } );

    test( 'a failing delete is swallowed: an orphan row is cosmetic, a lost wake is not',
        () async {
      // Runs on every wake, so a platform hiccup here must not cost the
      // notification the whole chain exists to deliver.
      await expectLater(
        deleteLegacyWakeChannel( ( _ ) async => throw Exception( 'no such channel' ) ),
        completes );
    } );

    test( 'the delete is idempotent — safe on every wake, no "have I done this" flag',
        () async {
      final deleted = <String>[];
      Future<void> del( String id ) async => deleted.add( id );
      await deleteLegacyWakeChannel( del );
      await deleteLegacyWakeChannel( del );

      expect( deleted, [ 'lupin_fcm_wake', 'lupin_fcm_wake' ],
          reason: 'deleting an already-deleted channel is a no-op on Android' );
    } );
  } );
}
