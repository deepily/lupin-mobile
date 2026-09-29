import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/testing/test_keys.dart';
import '../../../shared/widgets/tts_pause_control.dart';
import '../../../services/asr/asr_service.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../../auth/domain/auth_bloc.dart';
import '../../auth/domain/auth_state.dart';
import '../../auth/domain/auth_event.dart';
import '../../agentic/domain/agentic_submission_bloc.dart';
import '../../agentic/presentation/agentic_hub_screen.dart';
import '../../broadcast/domain/broadcast_bloc.dart';
import '../../broadcast/presentation/broadcast_pane.dart';
import '../../claude_code/domain/claude_code_bloc.dart';
import '../../claude_code/presentation/session_list_screen.dart';
import '../../decision_proxy/presentation/trust_dashboard_screen.dart';
import '../../finished_tasks/domain/finished_tasks_bloc.dart';
import '../../finished_tasks/presentation/finished_tasks_screen.dart';
import '../../fleet/presentation/pane_host_screen.dart';
import '../../fleet_status/presentation/fleet_status_screen.dart';
import '../../holding_area/domain/holding_area_bloc.dart';
import '../../holding_area/presentation/holding_area_pane.dart';
import '../../task_list/domain/task_list_bloc.dart';
import '../../task_list/presentation/task_list_pane.dart';
import '../../docs/data/doc_repository.dart';
import '../../docs/presentation/doc_split_host.dart';
import '../../home/home_screen.dart';
import '../../notifications/presentation/inbox_screen.dart';
import '../../queue/presentation/queue_dashboard_screen.dart';
import '../../quick_ask/presentation/quick_ask_screen.dart';
import '../../settings/presentation/notification_audio_settings_screen.dart';
import '../../settings/presentation/notification_management_screen.dart';
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

/// The Home grid's destinations, in the grid's own top-to-bottom order
/// (row c59457f0 item 2). The Focus view is not in this list: the drawer
/// gives it a fixed entry of its own under Quick Ask (row 74a799c9), and
/// Notifications / Job Queue / Trust Dashboard fall under item 1.
///
/// 🔴 THE ROUTE WIRING MIRRORS `home_screen.dart` BLOC FOR BLOC, and the
/// asymmetry in it is deliberate there: the four polling panes build their bloc
/// INSIDE the route, because an app-root bloc would keep polling behind whatever
/// the operator is actually looking at; Broadcast takes the app-root bloc by
/// `.value`, because its ack tally arrives on a socket frame and has to outlive
/// the pane. Two doors to one screen must not disagree about that, so a change
/// to either side belongs on both.
///
/// TOP-LEVEL, not a method on the state, so a test can call each `builder` and
/// see WHICH screen an entry opens without mounting that screen's whole bloc
/// graph.
@visibleForTesting
List<FocusDrawerSurface> focusDrawerSurfaces( BuildContext context ) {
  return <FocusDrawerSurface>[
    FocusDrawerSurface( Icons.smart_toy_outlined, 'Agentic Jobs', ( _ ) => BlocProvider.value(
      value : context.read<AgenticSubmissionBloc>(),
      child : const AgenticHubScreen(),
    ) ),
    FocusDrawerSurface( Icons.terminal_outlined, 'Claude Code', ( _ ) => BlocProvider.value(
      value : context.read<ClaudeCodeBloc>(),
      child : const SessionListScreen(),
    ) ),
    FocusDrawerSurface( Icons.campaign_outlined, 'Broadcast', ( _ ) => Scaffold(
      appBar : AppBar( title: const Text( 'Broadcast' ) ),
      body   : BlocProvider<BroadcastBloc>.value(
        value : ServiceLocator.get<BroadcastBloc>(),
        child : const BroadcastPane(),
      ),
    ) ),
    FocusDrawerSurface( Icons.groups_outlined, 'Fleet Status', ( _ ) => FleetStatusScreen(
      blocFactory: ( _ ) => ServiceLocator.buildFleetStatusBloc(),
    ) ),
    FocusDrawerSurface( Icons.task_alt_outlined, 'Finished Tasks', ( _ ) => BlocProvider<FinishedTasksBloc>(
      create : ( _ ) => ServiceLocator.buildFinishedTasksBloc(),
      child  : const FinishedTasksScreen(),
    ) ),
    FocusDrawerSurface( Icons.checklist_outlined, 'Task List', ( _ ) => PaneHostScreen<TaskListBloc>(
      title       : 'Task List',
      pane        : const TaskListPane(),
      blocFactory : ( _ ) => ServiceLocator.buildTaskListBloc(),
    ) ),
    FocusDrawerSurface( Icons.inbox_outlined, 'Holding Area', ( _ ) => PaneHostScreen<HoldingAreaBloc>(
      title       : 'Holding Area',
      pane        : const HoldingAreaPane(),
      blocFactory : ( _ ) => ServiceLocator.buildHoldingAreaBloc(),
    ) ),
  ];
}

/// The drawer's settings block — NOT Home-grid surfaces, and listed after them
/// under their own divider. The stop-list entry is disabled when the service is
/// not registered, exactly as the pre-experiment drawer had it.
@visibleForTesting
List<FocusDrawerSurface> focusDrawerTools( BuildContext context ) {
  return <FocusDrawerSurface>[
    // Row 7cac3a17's deliverable gets its own entry rather than living two
    // taps inside 'Settings' — Rick asked for a dedicated view because the
    // bombardment is the thing he is trying to reach.
    FocusDrawerSurface( Icons.notifications_outlined, 'Notifications', ( _ ) =>
      NotificationManagementScreen(
        prefs    : ServiceLocator.get<NotificationPreferences>(),
        stopList : ServiceLocator.isRegistered<NotificationStopList>()
            ? ServiceLocator.get<NotificationStopList>()
            : null,
      ),
    ),
    FocusDrawerSurface( Icons.settings, 'Settings', ( _ ) => NotificationAudioSettingsScreen(
      prefs: ServiceLocator.get<NotificationPreferences>(),
    ) ),
    FocusDrawerSurface( Icons.filter_alt_outlined, 'Notification stop-list', ( _ ) =>
      NotificationFilterSettingsScreen( stopList: ServiceLocator.get<NotificationStopList>() ),
      enabled: ServiceLocator.isRegistered<NotificationStopList>(),
    ),
  ];
}

/// Whether the Focus drawer runs the SURFACES experiment (row c59457f0).
///
/// 🔴 TRUE ON RICK'S ORDER, 2026-09-26: *"a little bit of a UI layout tweak...
/// Hide them, don't delete them for now... preserve the old layout."* With it
/// true the drawer lists the Home grid's destinations top to bottom and leaves
/// out Inbox, Queue Dashboard and Trust Dashboard.
///
/// ⚠️ NOT a `const bool` like `_kShowTrustDashboard` in `home_screen.dart`, and
/// that difference is the whole point: a const cannot be flipped from a test,
/// so the "the flag restores the old drawer" test would have to re-implement
/// the drawer to say anything — which is a test of the test. This is the
/// DEFAULT, and [FocusModeScreen.surfacesExperiment] is the one switch that
/// overrides it. Nothing is deleted either way: `_legacyDrawer` still compiles
/// and is still exercised at `false`.
const bool kFocusDrawerSurfacesExperimentDefault = true;

/// The surfaces drawer's header. Rick has the final word on the wording, so it
/// is ONE string in ONE place — change it here and the drawer follows.
/// Candidates offered with row c59457f0 were "Surfaces", "Go to" and "Lupin".
const String kFocusDrawerHeader = 'Surfaces';

/// The Focus view's name, wherever it is shown: this screen's app bar, the
/// drawer entry and the Home grid card. ONE string, for the same reason as
/// [kFocusDrawerHeader] (Rick 2026-09-28, row 74a799c9: "Lupin AF Focus").
const String kLupinFocusTitle = 'Lupin AF Focus';

/// Whether the surfaces drawer offers a Home grid entry. Rick 2026-09-28 (row
/// 74a799c9): redundant now that the drawer lists every grid destination, so
/// it is HIDDEN, not deleted, like the Inbox and the two dashboards. The
/// legacy drawer keeps its own Home grid entry either way.
const bool kShowHomeGridInSurfacesDrawer = false;

/// The app's DEFAULT post-auth surface (Q1): vertical badge rail + chat
/// pane (Q11 Pattern A), pause/resume hold control bound to S1's streams,
/// the S4 voice composer gated on S2's `pendingPromptFor` signal, and a
/// drawer demoting the legacy surfaces (nothing deleted).
class FocusModeScreen extends StatefulWidget {
  /// Constructor seams (test injection); default to the service locator.
  final TtsOrchestrator? tts;
  final AsrService?      asr;

  /// THE one switch for row c59457f0's drawer experiment (ruling R1, Tiffany
  /// 2026-09-28). Null means [kFocusDrawerSurfacesExperimentDefault]; `false`
  /// restores the pre-experiment drawer, entry for entry.
  final bool? surfacesExperiment;

  const FocusModeScreen( { super.key, this.tts, this.asr, this.surfacesExperiment } );

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  late final TtsOrchestrator _tts;
  late final AsrService      _asr;

  /// The app bar sits OUTSIDE the split host, so the files button reaches it
  /// by key rather than by looking up the tree.
  final GlobalKey<DocSplitHostState> _splitKey = GlobalKey<DocSplitHostState>();

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

  /// Resolved once, here, so no widget below asks the question twice.
  bool get _surfaces => widget.surfacesExperiment ?? kFocusDrawerSurfacesExperimentDefault;

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
            tooltip   : _surfaces ? kFocusDrawerHeader : 'Legacy screens',
            onPressed : () => Scaffold.of( ctx ).openDrawer(),
          ),
        ),
        title   : const Text( kLupinFocusTitle ),
        actions : [
          // Rick 2026-09-17: re-read the written-senders list AND the live-seat
          // roster, so a seat that has never messaged him can still be reached.
          IconButton(
            key       : const Key( TestKeys.focusRosterRefreshButton ),
            icon      : const Icon( Icons.refresh ),
            tooltip   : 'Refresh sessions',
            onPressed : () => context
                .read<FocusChatBloc>()
                .add( const FocusRosterRefreshRequested() ),
          ),
          // Row 0534b50d (parity with web row 47759aa3): a way into the file
          // viewer — and so into Upload — without digging up an old doc link.
          // It opens in the same split as a tapped doc link.
          IconButton(
            key       : const Key( TestKeys.focusFilesButton ),
            icon      : const Icon( Icons.folder_open ),
            tooltip   : 'Files',
            onPressed : () => _splitKey.currentState?.openRoots(),
          ),
          _QueueButton( tts: _tts ),
          // AC-S3.5c — the promoted shared control; behavior is asserted in
          // test/widget/shared/pause_control_test.dart, not here.
          TtsPauseToggle( tts: _tts, toggleKey: const Key( TestKeys.focusPauseToggle ) ),
        ],
      ),
      drawer: _surfaces ? _surfacesDrawer( context ) : _legacyDrawer( context ),
      body: Column(
        children: [
          TtsPausedBanner( tts: _tts, bannerKey: const Key( TestKeys.focusPausedBanner ) ),
          const FocusFilterBar(),
          // Rows 2416d2c5 / e0843a8a: a tapped doc link SHARES this space
          // with the conversation instead of floating over it, so the bubbles
          // reflow into their half. The composer below stays full width — it
          // writes to the focused session either way.
          Expanded(
            child: DocSplitHost(
              key       : _splitKey,
              repository: () => ServiceLocator.instance<DocRepository>(),
              prefs     : ServiceLocator.isRegistered<NotificationPreferences>()
                  ? ServiceLocator.get<NotificationPreferences>()
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SessionRail(),
                  const VerticalDivider( width: 1 ),
                  Expanded( child: FocusChatPane( userEmail: _authedEmail() ) ),
                ],
              ),
            ),
          ),
          // 🔴 P0 e5cc78ee, Rick 2026-09-23: with the soft keyboard up (Gboard plus
          // its voice strip runs 420 dp and more) and a spoken reply open for editing,
          // the composer was taller than the body left over. The outer Column then
          // overflowed, and the Send/X row sat BELOW the body's bounds: painted, but
          // never hit-tested, so both buttons were dead while everything above them
          // worked. Capped here and scrolled from the bottom, so the buttons are the
          // part that always stays on screen and the transcript is what scrolls.
          ConstrainedBox(
            constraints : BoxConstraints( maxHeight: _composerCap( context ) ),
            child       : SingleChildScrollView(
              key     : const Key( TestKeys.focusComposerScroll ),
              reverse : true,
              child   : _composer( context ),
            ),
          ),
        ],
      ),
    );
  }

  /// The most height the composer may take: 60% of what the keyboard leaves,
  /// but never less than one button row plus its caption.
  double _composerCap( BuildContext context ) {
    final mq      = MediaQuery.of( context );
    final visible = mq.size.height - mq.viewInsets.bottom - mq.padding.top - kToolbarHeight;
    return max( kVoiceReplyRowHeight + 32, visible * 0.6 );
  }

  /// S4 composer slot — UNGATED since 2026-08-21 (Rick: "send a voice
  /// message to a persona chip"): any focused session takes a voice/text
  /// message. With an unanswered ask it is a REPLY (the bloc's
  /// `pendingPromptFor` fallback resolves the target, F-S2-S2-3); without
  /// one it is a DIRECT MESSAGE through `POST /api/notify`, the same call the
  /// browsers make (Rick 2026-09-17). The caption says
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

  /// One drawer row off one [FocusDrawerSurface] — so the icon, the label, the
  /// key and the route can never be spelled differently between two entries.
  Widget _entryTile( BuildContext context, FocusDrawerSurface s ) {
    return ListTile(
      key     : Key( '${TestKeys.focusDrawerEntryPrefix}${s.title}' ),
      leading : Icon( s.icon ),
      title   : Text( s.title ),
      enabled : s.enabled,
      onTap   : () => _push( context, s.builder ),
    );
  }

  /// Close the drawer, then push [builder]'s route. Shared by both drawers so
  /// they cannot disagree about the pop-then-push order.
  void _push( BuildContext context, WidgetBuilder builder ) {
    Navigator.of( context ).pop();   // close the drawer first
    Navigator.of( context ).push( MaterialPageRoute<void>( builder: builder ) );
  }

  /// The SURFACES drawer (row c59457f0): Quick Ask and Lupin AF Focus on top
  /// (row 74a799c9; the Home grid entry is behind [kShowHomeGridInSurfacesDrawer]),
  /// then every Home-grid destination top to bottom, then Settings and the
  /// stop-list, then Log out. Inbox, Queue Dashboard and Trust Dashboard are
  /// ABSENT here and present in [_legacyDrawer] — hidden behind the switch,
  /// not deleted (Rick 2026-09-26: "Hide them, don't delete them for now").
  Drawer _surfacesDrawer( BuildContext context ) {
    return Drawer(
      child: ListView(
        children: [
          const DrawerHeader(
            key   : Key( TestKeys.focusDrawerHeader ),
            child : Text( kFocusDrawerHeader ),
          ),
          ListTile(
            key     : const Key( '${TestKeys.focusDrawerEntryPrefix}Quick Ask' ),
            leading : const Icon( Icons.mic ),
            title   : const Text( 'Quick Ask' ),
            onTap   : () => _push( context, ( _ ) => const QuickAskScreen() ),
          ),
          // Row 74a799c9: Focus is the landing screen and this drawer opens FROM
          // it, so the entry goes back to the first route instead of pushing a
          // second copy — the same door the Home grid card uses.
          //
          // 🔴 closeDrawer(), NOT Navigator.pop() (review F7). `pop()` closes a
          // drawer only as a side effect: DrawerController registers a
          // LocalHistoryEntry on open and pop() removes THAT rather than a route.
          // But the controller drops the entry the moment the close animation
          // turns around (drawer.dart, AnimationStatus.reverse), while the tile
          // stays mounted and hit-testable for the rest of the ~250 ms slide —
          // it is only clipped by an Align widthFactor. So a second tap in that
          // window found no history entry and popped the ROUTE: Focus is the
          // first and only route under MaterialApp.home, which left an empty
          // navigator and a black screen that only a restart cleared. An
          // ordinary double-tap, on the branch named for thumb fixes.
          //
          // closeDrawer() touches no routes and is idempotent, so the second tap
          // is harmless. popUntil stays as the belt to that braces: it is a
          // no-op while Focus is the first route, and still correct if a future
          // change ever opens this drawer from somewhere deeper.
          //
          // The Builder is load-bearing: `context` here is FocusModeScreen's own
          // build context, which is ABOVE the Scaffold this drawer belongs to, so
          // Scaffold.of() on it throws. The app bar's menu button already takes a
          // Builder context for openDrawer() for the same reason.
          Builder(
            builder: ( drawerCtx ) => ListTile(
              key     : const Key( '${TestKeys.focusDrawerEntryPrefix}$kLupinFocusTitle' ),
              leading : const Icon( Icons.center_focus_strong_outlined ),
              title   : const Text( kLupinFocusTitle ),
              onTap   : () {
                Scaffold.of( drawerCtx ).closeDrawer();
                Navigator.of( drawerCtx ).popUntil( ( route ) => route.isFirst );
              },
            ),
          ),
          if ( kShowHomeGridInSurfacesDrawer )
            ListTile(
              key     : const Key( '${TestKeys.focusDrawerEntryPrefix}Home grid' ),
              leading : const Icon( Icons.grid_view ),
              title   : const Text( 'Home grid' ),
              onTap   : () => _push( context, ( _ ) => const LupinHomeScreen() ),
            ),
          const Divider(),
          for ( final s in focusDrawerSurfaces( context ) ) _entryTile( context, s ),
          const Divider(),
          for ( final s in focusDrawerTools( context ) ) _entryTile( context, s ),
          const Divider(),
          ListTile(
            key     : const Key( TestKeys.focusDrawerLogout ),
            leading : const Icon( Icons.logout ),
            title   : const Text( 'Log out' ),
            onTap   : () {
              Navigator.of( context ).pop();   // close the drawer first
              context.read<AuthBloc>().add( const AuthLogoutRequested() );
            },
          ),
        ],
      ),
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
          // Quick Ask sits under the 'Legacy surfaces' header for round 1.
          // That reads oddly for the round-1 headline feature and is
          // DELIBERATE: the drawer is the only navigation surface the app has,
          // and renaming the header or minting a non-legacy entry point is a
          // navigation change that belongs with round 2's multi-job card view.
          ListTile(
            leading : const Icon( Icons.mic ),
            title   : const Text( 'Quick Ask' ),
            onTap   : () => push( const QuickAskScreen() ),
          ),
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
            leading : const Icon( Icons.notifications_outlined ),
            title   : const Text( 'Notifications' ),
            onTap   : () => push( NotificationManagementScreen(
              prefs    : ServiceLocator.get<NotificationPreferences>(),
              stopList : ServiceLocator.isRegistered<NotificationStopList>()
                  ? ServiceLocator.get<NotificationStopList>()
                  : null,
            ) ),
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
          // Rick 2026-09-23: "no explicit or easily found way of logging out" —
          // this is the landing screen, and Logout lived only on the Home grid.
          const Divider(),
          ListTile(
            key     : const Key( TestKeys.focusDrawerLogout ),
            leading : const Icon( Icons.logout ),
            title   : const Text( 'Log out' ),
            onTap   : () {
              Navigator.of( context ).pop();   // close the drawer first
              context.read<AuthBloc>().add( const AuthLogoutRequested() );
            },
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

/// One row of the surfaces drawer: its icon and label, the route it opens, and
/// whether it is tappable. Kept as DATA so the drawer's order is one list to
/// read rather than nine `ListTile`s to scan — and so a test can ask an entry
/// which screen it opens.
class FocusDrawerSurface {
  final IconData      icon;
  final String        title;
  final WidgetBuilder builder;
  final bool          enabled;
  const FocusDrawerSurface( this.icon, this.title, this.builder, { this.enabled = true } );
}
