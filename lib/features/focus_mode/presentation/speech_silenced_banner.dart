import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import '../../settings/presentation/notification_audio_settings_screen.dart';
import '../../settings/presentation/notification_management_screen.dart';
import 'focus_mode_screen.dart' show heartbeatPokeRepository, muteRosterLoader, pushPauseRepository;

/// Which screen holds the switch behind a [SpeechSilencer].
enum SilencerHome {
  /// The Notifications screen.
  notifications,
  /// The Settings (Notification audio) screen.
  settings,
  /// The conversation screen itself: the TTS slider is already on it.
  here,
}

/// One whole-phone reason the phone is not speaking.
class SpeechSilencer {
  /// The widget key of its row.
  final String key;
  /// What the row says, in plain words.
  final String words;
  /// Where the switch lives.
  final SilencerHome home;

  /// Creates a silencer description.
  const SpeechSilencer( this.key, this.words, this.home );
}

/// Marker on the conversation screen, shown whenever a whole-phone silencer is active.
///
/// It names each active silencer and a tap opens the screen that holds that switch:
///   - Notifications off
///   - Master mute on
///   - TTS slider at 0%
///   - quiet hours in effect now
///
/// Per-sender mutes, per-priority switches and the stop-list are not here: they silence some messages, not the phone.
///
/// The preferences have no change notification, and quiet hours change with the clock, so the marker
/// re-reads them once a second and repaints only when the set of active silencers changes.
class SpeechSilencedBanner extends StatefulWidget {
  /// Where the switches are read.
  final NotificationPreferences prefs;

  /// The clock, injectable for tests.
  final DateTime Function() now;

  /// Opens the Notifications screen; null pushes the same screen the drawer's Notifications row opens.
  final VoidCallback? onOpenNotifications;

  /// Opens the Settings screen; null pushes the same screen the drawer's Settings row opens.
  final VoidCallback? onOpenSettings;

  /// How often the preferences are re-read.
  final Duration poll;

  /// Creates the marker over [prefs].
  const SpeechSilencedBanner( {
    super.key,
    required this.prefs,
    this.now = DateTime.now,
    this.onOpenNotifications,
    this.onOpenSettings,
    this.poll = const Duration( seconds: 1 ),
  } );

  /// The active whole-phone silencers at [now], most blunt first.
  ///
  /// Ensures:
  ///   - only the four whole-phone silencers are ever returned
  static List<SpeechSilencer> activeSilencers( NotificationPreferences prefs, DateTime now ) {
    return <SpeechSilencer>[
      if ( !prefs.enabled )
        const SpeechSilencer( TestKeys.focusSilencedNotificationsOff, 'Notifications are off', SilencerHome.notifications ),
      if ( prefs.masterMute )
        const SpeechSilencer( TestKeys.focusSilencedMasterMute, 'Master mute is on', SilencerHome.settings ),
      if ( prefs.ttsFraction <= 0 )
        const SpeechSilencer( TestKeys.focusSilencedSliderZero, 'the TTS slider is at 0%', SilencerHome.here ),
      if ( prefs.inQuietHours( now ) )
        SpeechSilencer(
          TestKeys.focusSilencedQuietHours,
          // Urgent messages pass quiet hours while the bypass is on (the default), so the row must not overstate.
          prefs.quietUrgentBypass
              ? 'Quiet hours are in effect (urgent messages still speak)'
              : 'Quiet hours are in effect',
          SilencerHome.notifications,
        ),
    ];
  }

  @override
  State<SpeechSilencedBanner> createState() => _SpeechSilencedBannerState();
}

class _SpeechSilencedBannerState extends State<SpeechSilencedBanner> {
  Timer?                _timer;
  List<SpeechSilencer>  _active = const [];

  @override
  void initState() {
    super.initState();
    _active = _read();
    _timer  = Timer.periodic( widget.poll, ( _ ) => _recheck() );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<SpeechSilencer> _read() => SpeechSilencedBanner.activeSilencers( widget.prefs, widget.now() );

  void _recheck() {
    final next = _read();
    final same = next.length == _active.length &&
        Iterable<int>.generate( next.length ).every( ( i ) => next[ i ].key == _active[ i ].key );
    if ( !same && mounted ) setState( () => _active = next );
  }

  /// Pushes the Notifications screen with the same sections the drawer's row gives it.
  void _openNotifications() {
    Navigator.of( context ).push( MaterialPageRoute<void>(
      builder : ( _ ) => NotificationManagementScreen(
        prefs         : widget.prefs,
        stopList      : ServiceLocator.isRegistered<NotificationStopList>()
            ? ServiceLocator.get<NotificationStopList>()
            : null,
        loadSenders   : muteRosterLoader( context ),
        pushPause     : pushPauseRepository(),
        heartbeatPoke : heartbeatPokeRepository(),
      ),
    ) );
  }

  /// Pushes the Settings (Notification audio) screen.
  void _openSettings() {
    Navigator.of( context ).push( MaterialPageRoute<void>(
      builder : ( _ ) => NotificationAudioSettingsScreen( prefs: widget.prefs ),
    ) );
  }

  void _open( SilencerHome home ) {
    switch ( home ) {
      case SilencerHome.notifications:
        ( widget.onOpenNotifications ?? _openNotifications )();
      case SilencerHome.settings:
        ( widget.onOpenSettings ?? _openSettings )();
      case SilencerHome.here:
        break;
    }
  }

  @override
  Widget build( BuildContext context ) {
    if ( _active.isEmpty ) return const SizedBox.shrink();
    final scheme = Theme.of( context ).colorScheme;
    return Material(
      key   : const Key( TestKeys.focusSilencedBanner ),
      color : scheme.errorContainer,
      child : Column(
        crossAxisAlignment : CrossAxisAlignment.stretch,
        children : [
          for ( final s in _active )
            InkWell(
              key   : Key( s.key ),
              onTap : s.home == SilencerHome.here ? null : () => _open( s.home ),
              child : Padding(
                padding : const EdgeInsets.symmetric( horizontal: 12, vertical: 8 ),
                child   : Row(
                  children : [
                    Icon( Icons.volume_off, size: 18, color: scheme.onErrorContainer ),
                    const SizedBox( width: 8 ),
                    Expanded(
                      child : Text(
                        s.home == SilencerHome.here
                            ? 'Speech is silenced: ${s.words}. Move it up to hear messages.'
                            : 'Speech is silenced: ${s.words}. Tap to change.',
                        style : TextStyle( color: scheme.onErrorContainer ),
                      ),
                    ),
                    if ( s.home != SilencerHome.here )
                      Icon( Icons.chevron_right, color: scheme.onErrorContainer ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
