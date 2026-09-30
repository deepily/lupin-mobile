/// Long-press "Mute <sender>" shortcut (row f1e80e67, plan §7.5).
///
/// The annoyance happens where a notification is READ, so the fix lives there:
/// long-press a Focus bubble or an Inbox sender row, and a small sheet offers
/// "Mute <label>" (or "Unmute <label>" when that sender is already muted). The
/// choice is confirmed with a SnackBar whose Undo puts things back.
///
/// The key and label come from `notification_sender_label.dart`, so a mute made
/// here is the same mute the settings screen lists and the delivery policy reads.
library;

import 'package:flutter/material.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../../../services/push/notification_sender_label.dart';
import '../data/voice_persona.dart';

/// The notification-shaped map the sender helpers read, built from what a
/// screen has at hand.
///
/// Requires:
///   - senderId is the sender's full id, may be empty
///
/// Ensures:
///   - carries `sender_id`, and `voice_persona` only when [persona] is non-null
Map<String, dynamic> senderItemFor( String senderId, VoicePersona? persona ) => {
  "sender_id"     : senderId,
  if ( persona != null ) "voice_persona" : persona.toJson(),
};

/// Offer mute / unmute for the sender in [item].
///
/// Requires:
///   - context is mounted and under a Scaffold
///   - [prefs] is given, or NotificationPreferences is registered in ServiceLocator
///
/// Ensures:
///   - does nothing when [item] identifies no sender, or no prefs are available
///   - a chosen action writes the prefs, then shows a SnackBar with Undo
///   - Undo reverses exactly that action
Future<void> showMuteSenderMenu(
  BuildContext context, {
  required Map<String, dynamic> item,
  NotificationPreferences?      prefs,
} ) async {
  final key = notificationSenderKey( item );
  if ( key == null ) return;

  final store = prefs ??
      ( ServiceLocator.isRegistered<NotificationPreferences>()
          ? ServiceLocator.get<NotificationPreferences>()
          : null );
  if ( store == null ) return;

  final label      = notificationSenderLabel( item );
  final wasMuted   = store.isSenderMuted( key );
  final messenger  = ScaffoldMessenger.of( context );

  final choose = await showModalBottomSheet<bool>(
    context: context,
    builder: ( sheet ) => SafeArea(
      child: ListTile(
        key     : Key( wasMuted ? TestKeys.senderUnmuteAction : TestKeys.senderMuteAction ),
        leading : Icon( wasMuted ? Icons.volume_up : Icons.volume_off ),
        title   : Text( wasMuted ? "Unmute $label" : "Mute $label" ),
        onTap   : () => Navigator.of( sheet ).pop( true ),
      ),
    ),
  );
  if ( choose != true ) return;

  if ( wasMuted ) {
    await store.unmuteSender( key );
  } else {
    await store.muteSender( key, label );
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar( SnackBar(
    content : Text( wasMuted ? "Unmuted $label" : "Muted $label" ),
    action  : SnackBarAction(
      key     : const Key( TestKeys.senderMuteUndo ),
      label   : "Undo",
      onPressed: () {
        if ( wasMuted ) {
          store.muteSender( key, label );
        } else {
          store.unmuteSender( key );
        }
      },
    ),
  ) );
}
