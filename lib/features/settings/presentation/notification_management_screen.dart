import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import 'notification_audio_settings_screen.dart';
import 'notification_filter_settings_screen.dart';

/// The notification management view (Rick 2026-09-28, row 7cac3a17 — "now that
/// everything's been proven to work I need to be able to manage how intrusive
/// the notifications are, because right now I'm getting bombarded").
///
/// Three levels, exactly as he described them: a master switch; under it one
/// switch per SURFACE — while the app is closed (the FCM wake path) and while
/// it is open (the in-app ding and spoken summary); and under each surface one
/// checkbox per PRIORITY.
///
/// 🔴 WHAT "OFF" MEANS HERE, IN ONE SENTENCE: the phone stays quiet, and
/// nothing is lost. A suppressed notification is never hidden from a list and
/// never marked played on the server, so every one of them is still waiting
/// the next time the app is opened. Silence, never deletion — the same rule on
/// both surfaces.
///
/// This screen owns whether a notification is RAISED. How a raised one SOUNDS
/// still belongs to the sound-and-speech screen, linked at the bottom.
class NotificationManagementScreen extends StatefulWidget {
  final NotificationPreferences prefs;

  /// The stop-list screen's dependency, passed through only so this screen can
  /// offer the link. Null hides the link — a caller that has no stop-list
  /// registered should not render a row that would crash on tap.
  final NotificationStopList? stopList;

  const NotificationManagementScreen( {
    super.key,
    required this.prefs,
    this.stopList,
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

  /// Flip and rebuild immediately, fire the write in parallel. Same pattern as
  /// the sound screen: SharedPreferences is eventually consistent, and a UI
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
