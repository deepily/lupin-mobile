import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../../core/build_info.dart';
import '../../../core/build_info_footer.dart';
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
import '../../notifications/data/notification_repository.dart';
import '../../settings/data/heartbeat_poke_repository.dart';
import '../../settings/data/push_pause_repository.dart';
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

/// The Home grid's destinations, in the grid's own top-to-bottom order.
///
/// The Focus view is not in this list: the drawer gives it a fixed entry of its own under
/// Quick Ask. Notifications, Job Queue and Trust Dashboard are left out of the surfaces
/// drawer.
///
/// The route wiring mirrors `home_screen.dart` bloc for bloc.
/// The four polling panes build their bloc inside the route, because an app-root bloc would
/// keep polling behind whatever the operator is looking at.
/// Broadcast takes the app-root bloc by `.value`, because its ack tally arrives on a socket
/// frame and has to outlive the pane.
/// Two doors to one screen must not disagree, so a change to either side belongs on both.
///
/// It is top-level, not a method on the state.
/// A test can then call each `builder` and see which screen an entry opens without mounting
/// that screen's whole bloc graph.
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

/// Builds the roster loader the notification view offers for muting.
///
/// The roster is every sender the server has seen for this user, one row per mute key.
///
/// Ensures:
///   - null when nobody is signed in or no repository is registered, which
///     hides the view's Add button instead of offering a list that cannot load
Future<List<MutableSender>> Function()? muteRosterLoader( BuildContext context ) {
  final auth = context.read<AuthBloc>().state;
  if ( auth is! AuthAuthenticated ) return null;
  if ( !ServiceLocator.isRegistered<NotificationRepository>() ) return null;
  final email = auth.email;
  return () async => MutableSender.fromRoster(
      await ServiceLocator.get<NotificationRepository>().sendersVisible( email ) );
}

/// The server push-pause client, or null when none is registered (hides the section).
PushPauseRepository? pushPauseRepository() =>
    ServiceLocator.isRegistered<PushPauseRepository>()
        ? ServiceLocator.get<PushPauseRepository>()
        : null;

/// The stop poke client, or null when none is registered (hides the section).
HeartbeatPokeRepository? heartbeatPokeRepository() =>
    ServiceLocator.isRegistered<HeartbeatPokeRepository>()
        ? ServiceLocator.get<HeartbeatPokeRepository>()
        : null;

/// The drawer's settings block, listed after the Home-grid surfaces under their own divider.
///
/// The stop-list entry is disabled when the service is not registered.
@visibleForTesting
List<FocusDrawerSurface> focusDrawerTools( BuildContext context ) {
  return <FocusDrawerSurface>[
    // Notifications gets its own entry rather than living two taps inside Settings.
    FocusDrawerSurface( Icons.notifications_outlined, 'Notifications', ( _ ) =>
      NotificationManagementScreen(
        prefs       : ServiceLocator.get<NotificationPreferences>(),
        stopList    : ServiceLocator.isRegistered<NotificationStopList>()
            ? ServiceLocator.get<NotificationStopList>()
            : null,
        loadSenders : muteRosterLoader( context ),
        pushPause   : pushPauseRepository(),
        heartbeatPoke : heartbeatPokeRepository(),
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

/// Whether the Focus drawer runs the surfaces experiment by default.
///
/// It is true. With it true the drawer lists the Home grid's destinations top to bottom.
/// Inbox, Queue Dashboard and Trust Dashboard are left out, hidden and not deleted.
///
/// It is a default, not a `const bool` flag like `_kShowTrustDashboard` in `home_screen.dart`.
/// A const cannot be flipped from a test.
/// [FocusModeScreen.surfacesExperiment] is the one switch that overrides it.
/// `_legacyDrawer` still compiles and is still exercised when the switch is false.
const bool kFocusDrawerSurfacesExperimentDefault = true;

/// The surfaces drawer's header, kept as one string in one place so the drawer follows it.
const String kFocusDrawerHeader = 'Surfaces';

/// The Focus view's name, wherever it is shown.
///
/// It appears on this screen's app bar, the drawer entry and the Home grid card, and is one
/// string for the same reason as [kFocusDrawerHeader].
const String kLupinFocusTitle = 'Lupin AF Focus';

/// Whether the surfaces drawer offers a Home grid entry.
///
/// It is redundant now that the drawer lists every grid destination, so it is hidden, not
/// deleted, like the Inbox and the two dashboards.
/// The legacy drawer keeps its own Home grid entry either way.
const bool kShowHomeGridInSurfacesDrawer = false;

/// The app's default post-auth surface.
///
/// It shows a vertical badge rail beside a chat pane, a pause and resume hold control bound
/// to the speech streams, and a voice composer.
/// A drawer demotes the legacy surfaces without deleting them.
class FocusModeScreen extends StatefulWidget {
  /// The speech orchestrator; a test seam that defaults to the service locator.
  final TtsOrchestrator? tts;

  /// The speech-recognition service; a test seam that defaults to the service locator.
  final AsrService?      asr;

  /// The one switch for the drawer experiment.
  ///
  /// Null means [kFocusDrawerSurfacesExperimentDefault]. False restores the legacy drawer,
  /// entry for entry.
  final bool? surfacesExperiment;

  /// Creates the Focus screen; every argument is optional.
  const FocusModeScreen( { super.key, this.tts, this.asr, this.surfacesExperiment } );

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  late final TtsOrchestrator _tts;
  late final AsrService      _asr;

  /// Reaches the split host from the app bar's files button.
  ///
  /// The app bar sits outside the split host, so the button uses this key instead of looking
  /// up the tree.
  final GlobalKey<DocSplitHostState> _splitKey = GlobalKey<DocSplitHostState>();

  @override
  void initState() {
    super.initState();
    _tts = widget.tts ?? ServiceLocator.get<TtsOrchestrator>();
    _asr = widget.asr ?? ServiceLocator.get<AsrService>();

    // Cold start, guarded so the `auth_success` re-hydration dispatch in `app.dart` is not
    // duplicated on a warm bloc.
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
          // Re-reads the written-senders list and the live-seat roster, so a seat that has
          // never messaged the user can still be reached.
          IconButton(
            key       : const Key( TestKeys.focusRosterRefreshButton ),
            icon      : const Icon( Icons.refresh ),
            tooltip   : 'Refresh sessions',
            onPressed : () => context
                .read<FocusChatBloc>()
                .add( const FocusRosterRefreshRequested() ),
          ),
          // A way into the file viewer, and so into Upload, without digging up an old doc
          // link. It opens in the same split as a tapped doc link.
          IconButton(
            key       : const Key( TestKeys.focusFilesButton ),
            icon      : const Icon( Icons.folder_open ),
            tooltip   : 'Files',
            onPressed : () => _splitKey.currentState?.openRoots(),
          ),
          _QueueButton( tts: _tts ),
          // The shared pause control; its behavior is asserted in
          // `test/widget/shared/pause_control_test.dart`, not here.
          TtsPauseToggle( tts: _tts, toggleKey: const Key( TestKeys.focusPauseToggle ) ),
        ],
      ),
      drawer: _surfaces ? _surfacesDrawer( context ) : _legacyDrawer( context ),
      body: Column(
        children: [
          TtsPausedBanner( tts: _tts, bannerKey: const Key( TestKeys.focusPausedBanner ) ),
          const FocusFilterBar(),
          // A tapped doc link shares this space with the conversation instead of floating
          // over it, so the bubbles reflow into their half. The composer below stays full
          // width because it writes to the focused session either way.
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
          // With the soft keyboard up (a keyboard plus its voice strip can run 420 dp and
          // more) and a reply open for editing, the composer can be taller than the body
          // left over. The outer Column would then overflow and the Send and close row would
          // sit below the body's bounds, painted but never hit-tested, so both buttons are
          // dead. The cap and the bottom-anchored scroll keep the buttons on screen and let
          // the transcript scroll instead.
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

  /// The most height the composer may take.
  ///
  /// It is 60% of what the keyboard leaves, but never less than one button row plus its
  /// caption.
  double _composerCap( BuildContext context ) {
    final mq      = MediaQuery.of( context );
    final visible = mq.size.height - mq.viewInsets.bottom - mq.padding.top - kToolbarHeight;
    return max( kVoiceReplyRowHeight + 32, visible * 0.6 );
  }

  /// The composer slot, which any focused session accepts.
  ///
  /// With an unanswered ask, Send is a reply, and the bloc's `pendingPromptFor` fallback
  /// resolves the target. Without one, Send is a direct message through `POST /api/notify`,
  /// the same call the browsers make.
  /// The caption says which, so the user knows what Send will do.
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
                // The bloc resolves the pending ask (reply) or falls through to a direct message.
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

  /// One drawer row off one [FocusDrawerSurface].
  ///
  /// The icon, label, key and route come from one place, so two entries cannot spell them
  /// differently.
  Widget _entryTile( BuildContext context, FocusDrawerSurface s ) {
    return ListTile(
      key     : Key( '${TestKeys.focusDrawerEntryPrefix}${s.title}' ),
      leading : Icon( s.icon ),
      title   : Text( s.title ),
      enabled : s.enabled,
      onTap   : () => _push( context, s.builder ),
    );
  }

  /// Closes the drawer, then pushes [builder]'s route.
  ///
  /// Both drawers share it, so they cannot disagree about the pop-then-push order.
  void _push( BuildContext context, WidgetBuilder builder ) {
    Navigator.of( context ).pop();   // close the drawer first
    Navigator.of( context ).push( MaterialPageRoute<void>( builder: builder ) );
  }

  /// The surfaces drawer.
  ///
  /// Quick Ask and Lupin AF Focus come first, and the Home grid entry is behind
  /// [kShowHomeGridInSurfacesDrawer].
  /// Every Home-grid destination follows top to bottom, then Settings and the stop-list,
  /// then Log out.
  /// Inbox, Queue Dashboard and Trust Dashboard are absent here and present in
  /// [_legacyDrawer], hidden behind the switch and not deleted.
  Drawer _surfacesDrawer( BuildContext context ) {
    return Drawer(
      child: _withBuildFooter( ListView(
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
          // Focus is the landing screen and this drawer opens from it, so the entry goes back
          // to the first route instead of pushing a second copy, like the Home grid card.
          //
          // It calls closeDrawer(), not Navigator.pop(). A pop closes a drawer only as a side
          // effect: the drawer controller registers a local-history entry on open, and pop()
          // removes that rather than a route. The controller drops the entry when the close
          // animation turns around, while the tile stays tappable for the rest of the slide.
          // A second tap in that window popped the route itself, and Focus is the only route
          // under `MaterialApp.home`, which left an empty navigator and a black screen.
          //
          // closeDrawer() touches no routes and is idempotent, so a second tap is harmless.
          // popUntil stays as a backup: it is a no-op while Focus is the first route, and
          // still correct if the drawer is ever opened from somewhere deeper.
          //
          // The Builder is required: `context` here is above the Scaffold this drawer belongs
          // to, so `Scaffold.of()` on it throws. The app bar's menu button takes a Builder
          // context for the same reason.
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
      ) ),
    );
  }

  /// Pins the build line under [entries], so it stays on screen however long the list is.
  Widget _withBuildFooter( Widget entries ) {
    return Column(
      children: [
        Expanded( child: entries ),
        const Divider( height: 1 ),
        const SafeArea(
          top   : false,
          child : Padding(
            padding : EdgeInsets.symmetric( horizontal: 16, vertical: 10 ),
            child   : BuildInfoFooter( info: BuildInfo.current ),
          ),
        ),
      ],
    );
  }

  /// The pre-experiment drawer, kept entry for entry behind the experiment switch.
  Drawer _legacyDrawer( BuildContext context ) {
    final email = _authedEmail() ?? '';
    void push( Widget screen ) {
      Navigator.of( context ).pop();   // close the drawer first
      Navigator.of( context ).push(
        MaterialPageRoute<void>( builder: ( _ ) => screen ),
      );
    }

    return Drawer(
      child: _withBuildFooter( ListView(
        children: [
          const DrawerHeader( child: Text( 'Legacy surfaces' ) ),
          // Quick Ask sits under the legacy header. That reads oddly for a headline feature,
          // but the drawer is the only navigation surface the app has, and renaming the
          // header or adding a non-legacy entry point is a navigation change of its own.
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
              prefs       : ServiceLocator.get<NotificationPreferences>(),
              stopList    : ServiceLocator.isRegistered<NotificationStopList>()
                  ? ServiceLocator.get<NotificationStopList>()
                  : null,
              loadSenders : muteRosterLoader( context ),
              pushPause   : pushPauseRepository(),
              heartbeatPoke : heartbeatPokeRepository(),
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
          // Logout lives here because this is the landing screen.
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
      ) ),
    );
  }
}

/// App-bar speech-queue button with a live count badge; a tap opens [TtsQueueSheet].
///
/// The count comes from [TtsOrchestrator.queueDepthStream].
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

/// One row of the surfaces drawer, with its icon, label, route and tappable state.
///
/// It is data, so the drawer's order is one list to read and a test can ask an entry which
/// screen it opens.
class FocusDrawerSurface {
  /// The row's leading icon.
  final IconData      icon;

  /// The row's label.
  final String        title;

  /// Builds the screen the row opens.
  final WidgetBuilder builder;

  /// Whether the row can be tapped.
  final bool          enabled;

  /// Creates a drawer row; [enabled] defaults to true.
  const FocusDrawerSurface( this.icon, this.title, this.builder, { this.enabled = true } );
}
