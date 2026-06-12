import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../services/asr/asr_service.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../../auth/domain/auth_bloc.dart';
import '../../auth/domain/auth_state.dart';
import '../../decision_proxy/presentation/trust_dashboard_screen.dart';
import '../../home/home_screen.dart';
import '../../notifications/presentation/inbox_screen.dart';
import '../../queue/presentation/queue_dashboard_screen.dart';
import '../../settings/presentation/notification_audio_settings_screen.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';
import 'focus_chat_pane.dart';
import 'session_rail.dart';
import 'voice_reply_field.dart';

/// The app's DEFAULT post-auth surface (Q1): vertical badge rail + chat
/// pane (Q11 Pattern A), pause/resume hold control bound to S1's streams,
/// the S4 voice composer gated on S2's `pendingPromptFor` signal, and a
/// drawer demoting the legacy surfaces (nothing deleted).
class FocusModeScreen extends StatefulWidget {
  /// Constructor seams (test injection); default to the service locator.
  final TtsOrchestrator? tts;
  final AsrService?      asr;

  const FocusModeScreen( { super.key, this.tts, this.asr } );

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  late final TtsOrchestrator _tts;
  late final AsrService      _asr;

  @override
  void initState() {
    super.initState();
    _tts = widget.tts ?? ServiceLocator.get<TtsOrchestrator>();
    _asr = widget.asr ?? ServiceLocator.get<AsrService>();

    // Screen-init cold start (S2 §3.2) — guarded so the auth_success
    // re-hydration dispatch (app.dart) isn't duplicated on a warm bloc.
    final bloc  = context.read<FocusChatBloc>();
    final email = _authedEmail();
    if ( email != null &&
        bloc.state.senderOrder.isEmpty &&
        bloc.state.hydration == FocusHydration.idle ) {
      bloc.add( FocusColdStartRequested( userEmail: email ) );
    }
  }

  String? _authedEmail() {
    final auth = context.read<AuthBloc>().state;
    return auth is AuthAuthenticated ? auth.email : null;
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: ( ctx ) => IconButton(
            key       : const Key( TestKeys.focusDrawerButton ),
            icon      : const Icon( Icons.menu ),
            tooltip   : 'Legacy screens',
            onPressed : () => Scaffold.of( ctx ).openDrawer(),
          ),
        ),
        title   : const Text( 'Lupin Focus' ),
        actions : [ _PauseToggle( tts: _tts ) ],
      ),
      drawer: _legacyDrawer( context ),
      body: Column(
        children: [
          _PausedBanner( tts: _tts ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SessionRail(),
                const VerticalDivider( width: 1 ),
                Expanded( child: FocusChatPane( userEmail: _authedEmail() ) ),
              ],
            ),
          ),
          _composer( context ),
        ],
      ),
    );
  }

  /// S4 composer slot, gated on S2's `pendingPromptFor` contract-signal
  /// (F-S2-S2-3 — presentation choice owned here): active only when the
  /// focused sender has an unanswered ask; disabled + hint otherwise.
  Widget _composer( BuildContext context ) {
    return BlocBuilder<FocusChatBloc, FocusChatState>(
      builder: ( context, state ) {
        final focused = state.focusedSender;
        final pending =
            focused == null ? null : state.pendingPromptFor( focused );
        if ( focused == null || pending == null ) {
          return Container(
            padding : const EdgeInsets.all( 12 ),
            child   : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon( Icons.mic_off,
                    size  : 16,
                    color : Theme.of( context ).disabledColor ),
                const SizedBox( width: 8 ),
                Flexible(
                  child: Text(
                    focused == null
                        ? 'Focus a session to reply'
                        : 'No unanswered ask — voice reply unlocks when this session asks',
                    style: TextStyle( color: Theme.of( context ).disabledColor ),
                  ),
                ),
              ],
            ),
          );
        }
        final bloc = context.read<FocusChatBloc>();
        return Padding(
          padding: const EdgeInsets.symmetric( horizontal: 8 ),
          child: VoiceReplyField(
            asr      : _asr,
            // Voice replies intentionally omit promptContext — the bloc's
            // pendingPromptFor fallback resolves the target (F-S2-S2-3).
            onSubmit : ( text ) => bloc.add(
              FocusRespondRequested( senderId: focused, text: text ),
            ),
          ),
        );
      },
    );
  }

  Drawer _legacyDrawer( BuildContext context ) {
    final email = _authedEmail() ?? '';
    void push( Widget screen ) {
      Navigator.of( context ).pop();   // close the drawer first
      Navigator.of( context ).push(
        MaterialPageRoute<void>( builder: ( _ ) => screen ),
      );
    }

    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader( child: Text( 'Legacy surfaces' ) ),
          ListTile(
            leading : const Icon( Icons.grid_view ),
            title   : const Text( 'Home grid' ),
            onTap   : () => push( const LupinHomeScreen() ),
          ),
          ListTile(
            leading : const Icon( Icons.inbox ),
            title   : const Text( 'Inbox' ),
            onTap   : () => push( InboxScreen( userEmail: email ) ),
          ),
          ListTile(
            leading : const Icon( Icons.queue ),
            title   : const Text( 'Queue Dashboard' ),
            onTap   : () => push( const QueueDashboardScreen() ),
          ),
          ListTile(
            leading : const Icon( Icons.verified_user ),
            title   : const Text( 'Trust Dashboard' ),
            onTap   : () => push( TrustDashboardScreen( userEmail: email ) ),
          ),
          ListTile(
            leading : const Icon( Icons.settings ),
            title   : const Text( 'Settings' ),
            onTap   : () => push( NotificationAudioSettingsScreen(
              prefs: ServiceLocator.get<NotificationPreferences>(),
            ) ),
          ),
        ],
      ),
    );
  }
}

/// Pause/resume hold toggle bound to S1's `pausedStream` (Q6: a pause,
/// not a mute — see [_PausedBanner] for the held-count visibility).
class _PauseToggle extends StatelessWidget {
  final TtsOrchestrator tts;
  const _PauseToggle( { required this.tts } );

  @override
  Widget build( BuildContext context ) {
    return StreamBuilder<bool>(
      stream      : tts.pausedStream,
      initialData : tts.isPaused,
      builder: ( context, snap ) {
        final paused = snap.data ?? false;
        return IconButton(
          key       : const Key( TestKeys.focusPauseToggle ),
          tooltip   : paused ? 'Resume speech' : 'Hold speech',
          icon      : Icon( paused ? Icons.play_circle : Icons.pause_circle ),
          onPressed : () => paused ? tts.resume() : tts.pause(),
        );
      },
    );
  }
}

/// Loudly-visible paused state (Q6 held ≠ silent-forever) with the LIVE
/// held count off S1's `queueDepthStream` (F-S1-S2-3: ticks up as messages
/// accumulate under hold — held ≠ lost).
class _PausedBanner extends StatelessWidget {
  final TtsOrchestrator tts;
  const _PausedBanner( { required this.tts } );

  @override
  Widget build( BuildContext context ) {
    return StreamBuilder<bool>(
      stream      : tts.pausedStream,
      initialData : tts.isPaused,
      builder: ( context, pausedSnap ) {
        if ( pausedSnap.data != true ) return const SizedBox.shrink();
        return Material(
          key   : const Key( TestKeys.focusPausedBanner ),
          color : Theme.of( context ).colorScheme.tertiaryContainer,
          child : Padding(
            padding: const EdgeInsets.symmetric( horizontal: 12, vertical: 6 ),
            child: Row(
              children: [
                const Icon( Icons.pause, size: 16 ),
                const SizedBox( width: 8 ),
                StreamBuilder<int>(
                  stream      : tts.queueDepthStream,
                  initialData : tts.queueDepth,
                  builder: ( context, depthSnap ) => Text(
                    'Speech held — ${depthSnap.data ?? 0} message(s) queued',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
