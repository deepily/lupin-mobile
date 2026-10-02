import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/push/notification_sender_label.dart';
import '../../notifications/data/notification_models.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import '../data/heartbeat_poke_repository.dart';
import '../data/push_pause_repository.dart';
import 'notification_audio_settings_screen.dart';
import 'heartbeat_poke_section.dart';
import 'push_pause_section.dart';
import 'notification_filter_settings_screen.dart';

/// The notification management view: how intrusive the notifications are.
///
/// It has three levels. A master switch comes first, then one switch per surface, then
/// one checkbox per priority under each surface.
/// The surfaces are while the app is closed (the FCM wake path) and while it is open
/// (the in-app ding and spoken summary).
///
/// Off means the phone stays quiet and nothing is lost.
/// A suppressed notification is never hidden from a list.
/// Nor is it marked played on the server, so each one is still waiting the next time the
/// app opens.
/// This is silence, never deletion, on both surfaces.
///
/// This screen owns whether a notification is raised. How a raised one sounds belongs to
/// the sound-and-speech screen, linked at the bottom.
class NotificationManagementScreen extends StatefulWidget {
  /// The stored notification preferences this screen reads and writes.
  final NotificationPreferences prefs;

  /// The stop-list screen's dependency, passed through only so this screen can offer the link.
  ///
  /// Null hides the link, so a caller with no stop-list registered renders no row that
  /// would crash on tap.
  final NotificationStopList? stopList;

  /// Loads who can be muted: the senders the server knows about.
  ///
  /// Null hides the Add button; the list of already-muted senders, and removing them,
  /// still work without it.
  final Future<List<MutableSender>> Function()? loadSenders;

  /// The server push pause; null hides the section.
  final PushPauseRepository? pushPause;

  /// The fleet's stop poke switch; null hides the section.
  final HeartbeatPokeRepository? heartbeatPoke;

  /// Creates the screen over [prefs]; the other arguments switch sections on.
  const NotificationManagementScreen( {
    super.key,
    required this.prefs,
    this.stopList,
    this.loadSenders,
    this.pushPause,
    this.heartbeatPoke,
  } );

  @override
  State<NotificationManagementScreen> createState() =>
      _NotificationManagementScreenState();
}

class _NotificationManagementScreenState
    extends State<NotificationManagementScreen> {

  @override
  Widget build( BuildContext context ) {
    final p = widget.prefs;
    return Scaffold(
      appBar : AppBar( title: const Text( 'Notifications' ) ),
      body   : ListView(
        children: [
          if ( widget.pushPause != null )
            PushPauseSection( repository: widget.pushPause! ),
          if ( widget.heartbeatPoke != null )
            HeartbeatPokeSection( repository: widget.heartbeatPoke! ),
          SwitchListTile(
            key       : const Key( TestKeys.notifMgmtMaster ),
            secondary : const Icon( Icons.notifications_outlined ),
            title     : const Text( 'Notifications' ),
            subtitle  : const Text(
                'Off means the phone stays quiet everywhere. Nothing is lost — '
                'everything is still waiting in the app.' ),
            isThreeLine : true,
            value     : p.enabled,
            onChanged : ( v ) => _write( () => p.setEnabled( v ) ),
          ),
          const Divider(),

          _SurfaceSection(
            surface      : 'background',
            switchKey    : TestKeys.notifMgmtBackground,
            icon         : Icons.nightlight_outlined,
            title        : 'While the app is closed',
            subtitle     : 'Wake the phone in the background and post a notification.',
            surfaceValue : p.backgroundEnabled,
            masterOn     : p.enabled,
            prefs        : p,
            onSurface    : ( v ) => _write( () => p.setBackgroundEnabled( v ) ),
            onPriority   : ( priority, v ) =>
                _write( () => p.setPriorityEnabled( 'background', priority, v ) ),
          ),
          const Divider(),

          _SurfaceSection(
            surface      : 'foreground',
            switchKey    : TestKeys.notifMgmtForeground,
            icon         : Icons.phone_android_outlined,
            title        : 'While the app is open',
            subtitle     : 'Ding and speak as messages arrive. They still appear '
                           'in the list either way.',
            surfaceValue : p.foregroundEnabled,
            masterOn     : p.enabled,
            prefs        : p,
            onSurface    : ( v ) => _write( () => p.setForegroundEnabled( v ) ),
            onPriority   : ( priority, v ) =>
                _write( () => p.setPriorityEnabled( 'foreground', priority, v ) ),
          ),
          const Divider(),

          _MutedSendersSection(
            prefs       : p,
            masterOn    : p.enabled,
            loadSenders : widget.loadSenders,
            onChanged   : () => setState( () {} ),
          ),
          const Divider(),

          _QuietHoursSection(
            prefs     : p,
            masterOn  : p.enabled,
            onChanged : () => setState( () {} ),
          ),
          const Divider(),

          const _SectionHeader( 'More' ),
          ListTile(
            key      : const Key( TestKeys.notifMgmtOpenSound ),
            leading  : const Icon( Icons.volume_up_outlined ),
            title    : const Text( 'Sound and speech' ),
            subtitle : const Text( 'Which tone plays, and what gets read aloud.' ),
            trailing : const Icon( Icons.chevron_right ),
            onTap    : () => Navigator.of( context ).push( MaterialPageRoute(
              builder: ( _ ) => NotificationAudioSettingsScreen( prefs: p ),
            ) ),
          ),
          if ( widget.stopList != null )
            ListTile(
              key      : const Key( TestKeys.notifMgmtOpenStopList ),
              leading  : const Icon( Icons.filter_alt_outlined ),
              title    : const Text( 'Stop-list' ),
              subtitle : const Text( 'Hide and mute messages that start with a pattern.' ),
              trailing : const Icon( Icons.chevron_right ),
              onTap    : () => Navigator.of( context ).push( MaterialPageRoute(
                builder: ( _ ) =>
                    NotificationFilterSettingsScreen( stopList: widget.stopList! ),
              ) ),
            ),
          const SizedBox( height: 24 ),
        ],
      ),
    );
  }

  /// Rebuilds at once and fires the write in parallel.
  ///
  /// The sound screen does the same. SharedPreferences is eventually consistent, and a UI
  /// that waited on the disk would feel broken on every tap.
  void _write( Future<void> Function() write ) {
    setState( () {} );
    write();
  }
}

/// One surface: its own switch, then a checkbox per priority underneath.
class _SurfaceSection extends StatelessWidget {
  final String                    surface;
  final String                    switchKey;
  final IconData                  icon;
  final String                    title;
  final String                    subtitle;
  final bool                      surfaceValue;
  final bool                      masterOn;
  final NotificationPreferences   prefs;
  final ValueChanged<bool>        onSurface;
  final void Function( String priority, bool value ) onPriority;

  const _SurfaceSection( {
    required this.surface,
    required this.switchKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.surfaceValue,
    required this.masterOn,
    required this.prefs,
    required this.onSurface,
    required this.onPriority,
  } );

  @override
  Widget build( BuildContext context ) {
    // Cascade: the master switch greys the surface, and either of them greys
    // the priorities. Disabled rather than hidden, so the user can see what
    // their settings WOULD be — a section that vanished would make the master
    // switch look destructive.
    final prioritiesEnabled = masterOn && surfaceValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key       : Key( switchKey ),
          secondary : Icon( icon ),
          title     : Text( title ),
          subtitle  : Text( subtitle ),
          value     : surfaceValue,
          onChanged : masterOn ? onSurface : null,
        ),
        for ( final priority in NotificationPreferences.priorities )
          CheckboxListTile(
            key       : Key( TestKeys.notifMgmtPriority( surface, priority ) ),
            dense     : true,
            contentPadding : const EdgeInsets.only( left: 56, right: 16 ),
            controlAffinity: ListTileControlAffinity.leading,
            title     : Text( _priorityLabel( priority ) ),
            value     : prefs.priorityEnabled( surface, priority ),
            onChanged : prioritiesEnabled
                ? ( v ) => onPriority( priority, v ?? false )
                : null,
          ),
      ],
    );
  }

  String _priorityLabel( String priority ) => switch ( priority ) {
    'low'    => 'Low',
    'medium' => 'Medium',
    'high'   => 'High',
    'urgent' => 'Urgent',
    _        => priority,
  };
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader( this.text );

  @override
  Widget build( BuildContext context ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB( 16, 16, 16, 8 ),
      child: Text(
        text,
        style: Theme.of( context ).textTheme.labelLarge?.copyWith(
          color: Theme.of( context ).colorScheme.primary,
        ),
      ),
    );
  }
}

// ── Mute by sender and quiet hours ──

/// One sender that can be muted: the key the mute is stored under and the label read.
///
/// It is built with the same two functions the notification shade uses, so the list
/// shows the glyph and name exactly as the notification did.
class MutableSender {
  /// The key the mute is stored under.
  final String key;

  /// The label a person reads, as the notification shade shows it.
  final String label;

  /// Creates a sender from its mute [key] and display [label].
  const MutableSender( { required this.key, required this.label } );

  /// Collapses a server sender roster to one row per mute key.
  ///
  /// Requires:
  ///     - senders is the `senders-visible` roster, in the server's order
  ///
  /// Ensures:
  ///     - one entry per distinct `notificationSenderKey`, because two seats of one
  ///       persona, or two sessions of one project, are one thing to mute
  ///     - the first occurrence wins, so the server's order is preserved
  ///     - a sender that yields no key is left out (there is nothing to mute)
  static List<MutableSender> fromRoster( List<SenderSummary> senders ) {
    final seen = <String>{};
    final out  = <MutableSender>[];
    for ( final s in senders ) {
      final item = <String, dynamic>{
        'sender_id'     : s.senderId,
        if ( s.voicePersona != null ) 'voice_persona': s.voicePersona!.toJson(),
      };
      final key = notificationSenderKey( item );
      if ( key == null || !seen.add( key ) ) continue;
      out.add( MutableSender( key: key, label: notificationSenderLabel( item ) ) );
    }
    return out;
  }
}

class _MutedSendersSection extends StatelessWidget {
  final NotificationPreferences                 prefs;
  final bool                                    masterOn;
  final Future<List<MutableSender>> Function()? loadSenders;
  final VoidCallback                            onChanged;

  const _MutedSendersSection( {
    required this.prefs,
    required this.masterOn,
    required this.loadSenders,
    required this.onChanged,
  } );

  @override
  Widget build( BuildContext context ) {
    final muted = prefs.mutedSenders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading  : const Icon( Icons.volume_off_outlined ),
          title    : const Text( 'Muted senders' ),
          subtitle : Text( muted.isEmpty
              ? 'Nobody is muted.'
              : 'Their messages still arrive in the app, silently.' ),
          trailing : loadSenders == null
              ? null
              : TextButton.icon(
                  key       : const Key( TestKeys.notifMgmtMuteAdd ),
                  icon      : const Icon( Icons.add ),
                  label     : const Text( 'Add' ),
                  onPressed : masterOn ? () => _pick( context ) : null,
                ),
        ),
        for ( final e in muted.entries )
          ListTile(
            key            : Key( '${TestKeys.notifMgmtMuteRowPrefix}${e.key}' ),
            dense          : true,
            contentPadding : const EdgeInsets.only( left: 56, right: 8 ),
            title          : Text( e.value ),
            trailing       : IconButton(
              key       : Key( '${TestKeys.notifMgmtMuteRemovePrefix}${e.key}' ),
              icon      : const Icon( Icons.close ),
              tooltip   : 'Unmute',
              onPressed : () async {
                await prefs.unmuteSender( e.key );
                onChanged();
              },
            ),
          ),
        CheckboxListTile(
          key            : const Key( TestKeys.notifMgmtMuteUrgentBypass ),
          dense          : true,
          contentPadding : const EdgeInsets.only( left: 56, right: 16 ),
          controlAffinity: ListTileControlAffinity.leading,
          title          : const Text( 'Let urgent through from muted senders' ),
          value          : prefs.muteUrgentBypass,
          onChanged      : masterOn
              ? ( v ) async {
                  await prefs.setMuteUrgentBypass( v ?? true );
                  onChanged();
                }
              : null,
        ),
      ],
    );
  }

  /// Offer every sender the server knows about that is not muted yet.
  Future<void> _pick( BuildContext context ) async {
    final picked = await showModalBottomSheet<MutableSender>(
      context : context,
      builder : ( sheetContext ) => FutureBuilder<List<MutableSender>>(
        future  : loadSenders!(),
        builder : ( _, snap ) {
          if ( snap.connectionState != ConnectionState.done ) {
            return const SizedBox(
              height : 160,
              child  : Center( child: CircularProgressIndicator() ),
            );
          }
          final muted     = prefs.mutedSenders;
          final available = ( snap.data ?? const <MutableSender>[] )
              .where( ( s ) => !muted.containsKey( s.key ) )
              .toList();
          if ( available.isEmpty ) {
            return SizedBox(
              height : 160,
              child  : Center( child: Text( snap.hasError
                  ? 'Could not load senders.'
                  : 'No one else to mute.' ) ),
            );
          }
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const _SectionHeader( 'Mute which sender?' ),
                for ( final s in available )
                  ListTile(
                    key   : Key( '${TestKeys.notifMgmtMutePickPrefix}${s.key}' ),
                    title : Text( s.label ),
                    onTap : () => Navigator.of( sheetContext ).pop( s ),
                  ),
              ],
            ),
          );
        },
      ),
    );
    if ( picked == null ) return;
    await prefs.muteSender( picked.key, picked.label );
    onChanged();
  }
}

class _QuietHoursSection extends StatelessWidget {
  final NotificationPreferences prefs;
  final bool                    masterOn;
  final VoidCallback            onChanged;

  const _QuietHoursSection( {
    required this.prefs,
    required this.masterOn,
    required this.onChanged,
  } );

  @override
  Widget build( BuildContext context ) {
    final on = masterOn && prefs.quietEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key       : const Key( TestKeys.notifMgmtQuiet ),
          secondary : const Icon( Icons.bedtime_outlined ),
          title     : const Text( 'Quiet hours' ),
          subtitle  : const Text( 'Stay silent between these times, every day.' ),
          value     : prefs.quietEnabled,
          onChanged : masterOn
              ? ( v ) async {
                  await prefs.setQuietEnabled( v );
                  onChanged();
                }
              : null,
        ),
        Padding(
          padding : const EdgeInsets.only( left: 56, right: 16 ),
          child   : Row(
            children: [
              TextButton(
                key       : const Key( TestKeys.notifMgmtQuietStart ),
                onPressed : on ? () => _edit( context, start: true ) : null,
                child     : Text( formatMinutes( prefs.quietStartMinutes ) ),
              ),
              const Text( '→' ),
              TextButton(
                key       : const Key( TestKeys.notifMgmtQuietEnd ),
                onPressed : on ? () => _edit( context, start: false ) : null,
                child     : Text( formatMinutes( prefs.quietEndMinutes ) ),
              ),
            ],
          ),
        ),
        CheckboxListTile(
          key            : const Key( TestKeys.notifMgmtQuietUrgentBypass ),
          dense          : true,
          contentPadding : const EdgeInsets.only( left: 56, right: 16 ),
          controlAffinity: ListTileControlAffinity.leading,
          title          : const Text( 'Let urgent through during quiet hours' ),
          value          : prefs.quietUrgentBypass,
          onChanged      : on
              ? ( v ) async {
                  await prefs.setQuietUrgentBypass( v ?? true );
                  onChanged();
                }
              : null,
        ),
      ],
    );
  }

  Future<void> _edit( BuildContext context, { required bool start } ) async {
    final current = start ? prefs.quietStartMinutes : prefs.quietEndMinutes;
    final picked  = await showTimePicker(
      context     : context,
      initialTime : TimeOfDay( hour: current ~/ 60, minute: current % 60 ),
    );
    if ( picked == null ) return;
    final minutes = picked.hour * 60 + picked.minute;
    if ( start ) {
      await prefs.setQuietStartMinutes( minutes );
    } else {
      await prefs.setQuietEndMinutes( minutes );
    }
    onChanged();
  }
}

/// Formats minutes since midnight as 24-hour `HH:MM`, so `1320` becomes `22:00`.
///
/// A quiet window is read at a glance, and the 12-hour form is twice the width.
@visibleForTesting
String formatMinutes( int minutes ) {
  final h = ( minutes ~/ 60 ) % 24;
  final m = minutes % 60;
  return '${h.toString().padLeft( 2, '0' )}:${m.toString().padLeft( 2, '0' )}';
}
