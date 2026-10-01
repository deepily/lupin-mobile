import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../../core/di/service_locator.dart';
import '../../../services/asr/asr_service.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import 'notification_filter_settings_screen.dart';
import 'notification_management_screen.dart';
import 'round_trip_probe_screen.dart';

/// User-facing toggles for notification ding and spoken-summary behaviour.
///
/// It follows the Lupin web client's priority tiers. Medium is a ding only, high is a
/// ding plus speech, and urgent is a distinct ding plus speech.
/// Master mute overrides all.
class NotificationAudioSettingsScreen extends StatefulWidget {
  /// The stored notification preferences this screen reads and writes.
  final NotificationPreferences prefs;

  /// Resolves the kept-recordings folder shown under the debug switch.
  ///
  /// It is injectable because path_provider has no platform channel in tests.
  final Future<Directory> Function() keptRecordingsDir;

  /// Creates the screen over [prefs].
  const NotificationAudioSettingsScreen( {
    super.key,
    required this.prefs,
    this.keptRecordingsDir = AsrService.keptRecordingsDirectory,
  } );

  @override
  State<NotificationAudioSettingsScreen> createState() =>
      _NotificationAudioSettingsScreenState();
}

class _NotificationAudioSettingsScreenState
    extends State<NotificationAudioSettingsScreen> {

  late bool _masterMute;
  late bool _dingOnMedium;
  late bool _dingOnHigh;
  late bool _dingOnUrgent;
  late bool _speakOnHigh;
  late bool _speakSystem;
  late bool _speakOnUrgent;
  late bool _keepRecordings;
  String?   _keptDirPath;

  @override
  void initState() {
    super.initState();
    final p        = widget.prefs;
    _masterMute    = p.masterMute;
    _dingOnMedium  = p.dingOnMedium;
    _dingOnHigh    = p.dingOnHigh;
    _dingOnUrgent  = p.dingOnUrgent;
    _speakOnHigh   = p.speakOnHigh;
    _speakSystem   = p.speakSystemSenders;
    _speakOnUrgent = p.speakOnUrgent;
    _keepRecordings = p.keepVoiceRecordings;
    _resolveKeptDir();
  }

  Future<void> _resolveKeptDir() async {
    String path;
    try {
      path = ( await widget.keptRecordingsDir() ).path;
    } catch ( _ ) {
      path = 'unavailable on this device';
    }
    if ( mounted ) setState( () => _keptDirPath = path );
  }

  /// The toggle handlers below flip local state at once and fire the write in parallel.
  ///
  /// SharedPreferences is eventually consistent. A failed write shows up at the next
  /// getter on a cold restart, which is an acceptable trade-off here.
  void _toggleMasterMute(    bool v ) { setState( () => _masterMute    = v ); widget.prefs.setMasterMute(    v ); }
  void _toggleDingMedium(    bool v ) { setState( () => _dingOnMedium  = v ); widget.prefs.setDingOnMedium(  v ); }
  void _toggleDingHigh(      bool v ) { setState( () => _dingOnHigh    = v ); widget.prefs.setDingOnHigh(    v ); }
  void _toggleDingUrgent(    bool v ) { setState( () => _dingOnUrgent  = v ); widget.prefs.setDingOnUrgent(  v ); }
  void _toggleSpeakHigh(     bool v ) { setState( () => _speakOnHigh   = v ); widget.prefs.setSpeakOnHigh(   v ); }
  void _toggleSpeakUrgent(   bool v ) { setState( () => _speakOnUrgent = v ); widget.prefs.setSpeakOnUrgent( v ); }
  void _toggleSpeakSystem(   bool v ) { setState( () => _speakSystem   = v ); widget.prefs.setSpeakSystemSenders( v ); }
  void _toggleKeepRecordings( bool v ) { setState( () => _keepRecordings = v ); widget.prefs.setKeepVoiceRecordings( v ); }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Notification audio' ) ),
      body: ListView(
        children: [
          const _SectionHeader( 'Global' ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsMasterMute ),
            title      : const Text( 'Master mute' ),
            subtitle   : const Text( 'Silence every ding and spoken notification.' ),
            value      : _masterMute,
            onChanged  : _toggleMasterMute,
          ),
          const Divider(),
          const _SectionHeader( 'Ding (notification sound)' ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsDingMedium ),
            title      : const Text( 'Medium priority' ),
            subtitle   : const Text( 'Gentle ping — e.g. routine progress.' ),
            value      : _dingOnMedium,
            onChanged  : _toggleDingMedium,
          ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsDingHigh ),
            title      : const Text( 'High priority' ),
            subtitle   : const Text( 'Prominent ping — user attention needed.' ),
            value      : _dingOnHigh,
            onChanged  : _toggleDingHigh,
          ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsDingUrgent ),
            title      : const Text( 'Urgent' ),
            subtitle   : const Text( 'Distinct alert tone — action required now.' ),
            value      : _dingOnUrgent,
            onChanged  : _toggleDingUrgent,
          ),
          const Divider(),
          const _SectionHeader( 'Speak (on-device TTS)' ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsSpeakHigh ),
            title      : const Text( 'Speak high-priority' ),
            subtitle   : const Text( 'Read out the title and message after the ding.' ),
            value      : _speakOnHigh,
            onChanged  : _toggleSpeakHigh,
          ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsSpeakUrgent ),
            title      : const Text( 'Speak urgent' ),
            subtitle   : const Text( 'Read out the title and message after the ding.' ),
            value      : _speakOnUrgent,
            onChanged  : _toggleSpeakUrgent,
          ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsSpeakSystem ),
            title      : const Text( 'Speak system senders' ),
            subtitle   : const Text( 'Off = only sessions with a voice persona are spoken; test runners, hooks and scripts stay visible but silent.' ),
            value      : _speakSystem,
            onChanged  : _toggleSpeakSystem,
          ),
          const SizedBox( height: 24 ),
          const Divider(),
          // 🔴 THE WAKE SWITCH MOVED, IT DID NOT GO AWAY (row 7cac3a17 supersedes
          // row 1af7b3de). It is now the "while the app is closed" switch on the
          // notification management screen, which offers the same thing plus a
          // checkbox per priority. Leaving a second copy here would give the
          // user two controls over one setting, and this screen is about how a
          // notification SOUNDS, not whether it is raised.
          const _SectionHeader( 'While the app is closed' ),
          ListTile(
            key      : const Key( TestKeys.settingsOpenNotificationManagement ),
            leading  : const Icon( Icons.notifications_active_outlined ),
            title    : const Text( 'Which notifications to raise' ),
            subtitle : const Text(
                'Background and foreground, and which priorities each one may '
                'interrupt you for.' ),
            trailing : const Icon( Icons.chevron_right ),
            isThreeLine : true,
            onTap    : () => Navigator.of( context ).push( MaterialPageRoute(
              builder: ( _ ) => NotificationManagementScreen( prefs: widget.prefs ),
            ) ),
          ),
          const Divider(),
          const _SectionHeader( 'Filtering' ),
          ListTile(
            key      : const Key( TestKeys.settingsOpenStopList ),
            leading  : const Icon( Icons.filter_alt_outlined ),
            title    : const Text( 'Notification stop-list' ),
            subtitle : const Text( 'Hide + mute messages by prefix (e.g. tool-call chatter).' ),
            trailing : const Icon( Icons.chevron_right ),
            enabled  : ServiceLocator.isRegistered<NotificationStopList>(),
            onTap    : () => Navigator.of( context ).push( MaterialPageRoute(
              builder: ( _ ) => NotificationFilterSettingsScreen(
                stopList: ServiceLocator.get<NotificationStopList>(),
              ),
            ) ),
          ),
          const Divider(),
          // Visible in every build, release included: the owner measures on
          // release-ish builds. Labelled debug so nobody mistakes it for a setting.
          const _SectionHeader( 'Debug' ),
          ListTile(
            key      : const Key( TestKeys.settingsOpenRoundTripProbe ),
            leading  : const Icon( Icons.network_check ),
            title    : const Text( 'Network round-trip probe' ),
            subtitle : const Text( 'Debug: time 20 health calls and 30 s WAV uploads to the server.' ),
            trailing : const Icon( Icons.chevron_right ),
            enabled  : ServiceLocator.isRegistered<Dio>(),
            onTap    : () => Navigator.of( context ).push( MaterialPageRoute(
              builder: ( _ ) => RoundTripProbeScreen( dio: ServiceLocator.get<Dio>() ),
            ) ),
          ),
          SwitchListTile(
            key        : const Key( TestKeys.settingsKeepVoiceRecordings ),
            secondary  : const Icon( Icons.save_alt ),
            title      : const Text( 'Keep voice recordings' ),
            subtitle   : Text( 'Debug: save a WAV copy of each recording before it is deleted.\n'
                               'Folder: ${_keptDirPath ?? '…'}' ),
            isThreeLine : true,
            value      : _keepRecordings,
            onChanged  : _toggleKeepRecordings,
          ),
        ],
      ),
    );
  }
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
