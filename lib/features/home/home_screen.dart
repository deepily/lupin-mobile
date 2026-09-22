import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/service_locator.dart';
import '../../core/testing/test_keys.dart';
import '../../services/notification_audio/notification_preferences.dart';
import '../agentic/domain/agentic_submission_bloc.dart';
import '../agentic/presentation/agentic_hub_screen.dart';
import '../auth/domain/auth_bloc.dart';
import '../auth/domain/auth_event.dart';
import '../auth/domain/auth_state.dart';
import '../claude_code/domain/claude_code_bloc.dart';
import '../claude_code/presentation/session_list_screen.dart';
import '../decision_proxy/presentation/trust_dashboard_screen.dart';
import '../fleet_status/presentation/fleet_status_screen.dart';
import '../fleet/presentation/pane_host_screen.dart';
import '../task_list/domain/task_list_bloc.dart';
import '../task_list/presentation/task_list_pane.dart';
import '../holding_area/domain/holding_area_bloc.dart';
import '../holding_area/presentation/holding_area_pane.dart';
import '../finished_tasks/domain/finished_tasks_bloc.dart';
import '../finished_tasks/presentation/finished_tasks_screen.dart';
import '../broadcast/domain/broadcast_bloc.dart';
import '../broadcast/presentation/broadcast_pane.dart';
import '../notifications/presentation/inbox_screen.dart';
import '../queue/domain/queue_bloc.dart';
import '../queue/presentation/queue_dashboard_screen.dart';
import '../settings/presentation/notification_audio_settings_screen.dart';

class LupinHomeScreen extends StatelessWidget {
  const LupinHomeScreen( { super.key } );

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text( 'Lupin Mobile' ),
        actions: [
          IconButton(
            tooltip  : 'Inbox',
            icon     : const Icon( Icons.inbox_outlined ),
            onPressed: () {
              final s = context.read<AuthBloc>().state;
              if ( s is AuthAuthenticated ) {
                Navigator.of( context ).push( MaterialPageRoute(
                  builder: ( _ ) => InboxScreen( userEmail: s.email ),
                ) );
              }
            },
          ),
          IconButton(
            tooltip  : 'Trust',
            icon     : const Icon( Icons.shield_outlined ),
            onPressed: () {
              final s = context.read<AuthBloc>().state;
              if ( s is AuthAuthenticated ) {
                Navigator.of( context ).push( MaterialPageRoute(
                  builder: ( _ ) => TrustDashboardScreen( userEmail: s.email ),
                ) );
              }
            },
          ),
          IconButton(
            key      : const Key( TestKeys.homeSettingsButton ),
            tooltip  : 'Settings',
            icon     : const Icon( Icons.settings_outlined ),
            onPressed: () => Navigator.of( context ).push( MaterialPageRoute(
              builder: ( _ ) => NotificationAudioSettingsScreen(
                prefs: ServiceLocator.get<NotificationPreferences>(),
              ),
            ) ),
          ),
          IconButton(
            tooltip  : 'Logout',
            icon     : const Icon( Icons.logout ),
            onPressed: () => context.read<AuthBloc>().add( const AuthLogoutRequested() ),
          ),
        ],
      ),
      body: ListView( padding: const EdgeInsets.all( 16 ), children: [
        _NavCard(
          icon       : Icons.queue_outlined,
          title      : 'Job Queue',
          subtitle   : 'View and manage CJ Flow jobs',
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => BlocProvider.value(
              value: context.read<QueueBloc>(),
              child: const QueueDashboardScreen(),
            ),
          ) ),
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          icon       : Icons.terminal_outlined,
          title      : 'Claude Code',
          subtitle   : 'Interactive Claude Code sessions',
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => BlocProvider.value(
              value: context.read<ClaudeCodeBloc>(),
              child: const SessionListScreen(),
            ),
          ) ),
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          icon       : Icons.inbox_outlined,
          title      : 'Notifications',
          subtitle   : 'View notification inbox',
          onTap      : () {
            final s = context.read<AuthBloc>().state;
            if ( s is AuthAuthenticated ) {
              Navigator.of( context ).push( MaterialPageRoute(
                builder: ( _ ) => InboxScreen( userEmail: s.email ),
              ) );
            }
          },
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          icon       : Icons.shield_outlined,
          title      : 'Trust Dashboard',
          subtitle   : 'Manage decision proxy approvals',
          onTap      : () {
            final s = context.read<AuthBloc>().state;
            if ( s is AuthAuthenticated ) {
              Navigator.of( context ).push( MaterialPageRoute(
                builder: ( _ ) => TrustDashboardScreen( userEmail: s.email ),
              ) );
            }
          },
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          icon       : Icons.smart_toy_outlined,
          title      : 'Agentic Jobs',
          subtitle   : 'Submit deep research, podcast, presentation and more',
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => BlocProvider.value(
              value: context.read<AgenticSubmissionBloc>(),
              child: const AgenticHubScreen(),
            ),
          ) ),
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          key        : const Key( TestKeys.homeFleetStatusCard ),
          icon       : Icons.groups_outlined,
          title      : 'Fleet Status',
          subtitle   : 'Seats, liveness and the fleet-size cap',
          // 🔴 `BlocProvider( create: )` INSIDE THE ROUTE, not
          // `BlocProvider.value( context.read<…>() )` like every sibling above.
          // That is a decision, not an oversight: the Fleet Status bloc polls on
          // a 60-second timer, so a bloc held at the app root would keep polling
          // whichever pane the operator is actually looking at. Route-scoping is
          // what makes "a pane you have not opened issues no requests" true.
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => FleetStatusScreen(
              blocFactory: ( _ ) => ServiceLocator.buildFleetStatusBloc(),
            ),
          ) ),
        ),
        const SizedBox( height: 12 ),
        // 🔴 THE FOUR CARDS BELOW ARE THE DOOR THAT WAS NEVER BUILT. Phases 2-5 each
        // shipped a pane that was tested, merged and green — and referenced only by its
        // own file and its tests. Measured 2026-09-22; wired on Rick's go-ahead.
        //
        // ⚠️ Three of them build their bloc INSIDE the route, like Fleet Status above,
        // because they poll. Broadcast does NOT: its bloc is app-root, because acks
        // arrive on a socket frame only `app.dart` can route and its tally has to
        // survive leaving the pane. That asymmetry is deliberate and is explained at
        // both registration sites.
        _NavCard(
          key        : const Key( TestKeys.homeTaskListCard ),
          icon       : Icons.checklist_outlined,
          title      : 'Task List',
          subtitle   : 'The live board, grouped and orderable',
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => PaneHostScreen<TaskListBloc>(
              title       : 'Task List',
              pane        : const TaskListPane(),
              blocFactory : ( _ ) => ServiceLocator.buildTaskListBloc(),
            ),
          ) ),
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          key        : const Key( TestKeys.homeHoldingAreaCard ),
          icon       : Icons.inbox_outlined,
          title      : 'Holding Area',
          subtitle   : 'Work awaiting an approver, grouped by filer',
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => PaneHostScreen<HoldingAreaBloc>(
              title       : 'Holding Area',
              pane        : const HoldingAreaPane(),
              blocFactory : ( _ ) => ServiceLocator.buildHoldingAreaBloc(),
            ),
          ) ),
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          key        : const Key( TestKeys.homeFinishedTasksCard ),
          icon       : Icons.task_alt_outlined,
          title      : 'Finished Tasks',
          subtitle   : 'What closed, and how it closed',
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => BlocProvider<FinishedTasksBloc>(
              create : ( _ ) => ServiceLocator.buildFinishedTasksBloc(),
              // Its own Scaffold already — Phase 2 built a SCREEN, not a pane, which is
              // why it needs no PaneHostScreen and why it was easy to miscount as one.
              child  : const FinishedTasksScreen(),
            ),
          ) ),
        ),
        const SizedBox( height: 12 ),
        _NavCard(
          key        : const Key( TestKeys.homeBroadcastCard ),
          icon       : Icons.campaign_outlined,
          title      : 'Broadcast',
          subtitle   : 'Say something to the whole fleet at once',
          onTap      : () => Navigator.of( context ).push( MaterialPageRoute(
            // `.value`, NOT `create:` — the bloc is app-root and must NOT be disposed
            // when this route pops, or the ack tally dies with the screen.
            builder: ( _ ) => Scaffold(
              appBar : AppBar( title: const Text( 'Broadcast' ) ),
              body   : BlocProvider<BroadcastBloc>.value(
                value : ServiceLocator.get<BroadcastBloc>(),
                child : const BroadcastPane(),
              ),
            ),
          ) ),
        ),
      ] ),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;

  const _NavCard( {
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  } );

  @override
  Widget build( BuildContext context ) {
    return Card(
      child: ListTile(
        leading  : Icon( icon, size: 32 ),
        title    : Text( title ),
        subtitle : Text( subtitle ),
        trailing : const Icon( Icons.chevron_right ),
        onTap    : onTap,
      ),
    );
  }
}
