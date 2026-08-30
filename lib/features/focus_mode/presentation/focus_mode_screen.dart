import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../shared/widgets/tts_pause_control.dart';
import '../../../services/asr/asr_service.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../../auth/domain/auth_bloc.dart';
import '../../auth/domain/auth_state.dart';
import '../../decision_proxy/presentation/trust_dashboard_screen.dart';
import '../../home/home_screen.dart';
import '../../notifications/presentation/inbox_screen.dart';
import '../../queue/presentation/queue_dashboard_screen.dart';
import '../../settings/presentation/notification_audio_settings_screen.dart';
import '../../settings/presentation/notification_filter_settings_screen.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import '../../../services/notification_audio/notification_preferences.dart';
import '../domain/focus_chat_bloc.dart';
import '../domain/focus_chat_event.dart';
import '../domain/focus_chat_state.dart';
import 'focus_chat_pane.dart';
import 'focus_filter_bar.dart';
import 'session_rail.dart';
import 'tts_queue_sheet.dart';
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
        actions : [
          _QueueButton( tts: _tts ),
          // AC-S3.5c — the promoted shared control; behavior is asserted in
          // test/widget/shared/pause_control_test.dart, not here.
          TtsPauseToggle( tts: _tts, toggleKey: const Key( TestKeys.focusPauseToggle ) ),
        ],
      ),
      drawer: _legacyDrawer( context ),
      body: Column(
        children: [
          TtsPausedBanner( tts: _tts, bannerKey: const Key( TestKeys.focusPausedBanner ) ),
          const FocusFilterBar(),
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

  /// S4 composer slot — UNGATED since 2026-08-21 (Rick: "send a voice
  /// message to a persona chip"): any focused session takes a voice/text
  /// message. With an unanswered ask it is a REPLY (the bloc's
  /// `pendingPromptFor` fallback resolves the target, F-S2-S2-3); without
  /// one it is a DIRECT MESSAGE through `/api/dm/send`. The caption says
  /// which, so the user knows what Send will do.
  Widget _composer( BuildContext context ) {
    return BlocBuilder<FocusChatBloc, FocusChatState>(
      builder: ( context, state ) {
        final focused = state.focusedSender;
        if ( focused == null ) {
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
                    'Focus a session to reply or message it',
                    style: TextStyle( color: Theme.of( context ).disabledColor ),
                  ),
                ),
              ],
            ),
          );
        }
        final pending = state.pendingPromptFor( focused );
        final persona = state.personasBySender[ focused ];
        final who     = ( persona?.displayName ?? persona?.name ?? '' ).trim();
        final caption = pending != null
            ? 'Replying to ${who.isEmpty ? 'this session' : who}\'s question'
            : 'Direct message to ${who.isEmpty ? 'this session' : who}';
        final bloc = context.read<FocusChatBloc>();
        return Padding(
          padding: const EdgeInsets.symmetric( horizontal: 8 ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize      : MainAxisSize.min,
            children: [
              Padding(
                padding : const EdgeInsets.only( left: 4, top: 4 ),
                child   : Row(
                  children: [
                    Icon( pending != null ? Icons.reply : Icons.send,
                        size  : 12,
                        color : Theme.of( context ).colorScheme.outline ),
                    const SizedBox( width: 4 ),
                    Text(
                      caption,
                      key   : const Key( TestKeys.focusComposerCaption ),
                      style : Theme.of( context ).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              VoiceReplyField(
                asr      : _asr,
                // promptContext intentionally omitted — the bloc resolves
                // the pending ask (reply) or falls through to a DM.
                onSubmit : ( text ) => bloc.add(
                  FocusRespondRequested( senderId: focused, text: text ),
                ),
              ),
            ],
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
          ListTile(
            leading : const Icon( Icons.filter_alt_outlined ),
            title   : const Text( 'Notification stop-list' ),
            enabled : ServiceLocator.isRegistered<NotificationStopList>(),
            onTap   : () => push( NotificationFilterSettingsScreen(
              stopList: ServiceLocator.get<NotificationStopList>(),
            ) ),
          ),
        ],
      ),
    );
  }
}

/// App-bar speech-queue button (Rick 2026-08-21): live count badge off
/// [TtsOrchestrator.queueDepthStream]; tap opens [TtsQueueSheet].
class _QueueButton extends StatelessWidget {
  final TtsOrchestrator tts;
  const _QueueButton( { required this.tts } );

  @override
  Widget build( BuildContext context ) {
    return StreamBuilder<int>(
      stream      : tts.queueDepthStream,
      initialData : tts.queueDepth,
      builder: ( context, snap ) {
        final depth = snap.data ?? 0;
        return IconButton(
          key       : const Key( TestKeys.focusQueueButton ),
          tooltip   : 'Speech queue',
          onPressed : () => TtsQueueSheet.show( context, tts ),
          icon      : Badge(
            key       : const Key( TestKeys.focusQueueBadge ),
            isLabelVisible : depth > 0,
            label     : Text( '$depth' ),
            child     : const Icon( Icons.queue_music ),
          ),
        );
      },
    );
  }
}

