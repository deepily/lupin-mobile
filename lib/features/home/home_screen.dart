import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../auth/domain/auth_bloc.dart';
import '../auth/domain/auth_event.dart';
import '../auth/domain/auth_state.dart';
import '../claude_code/domain/claude_code_bloc.dart';
import '../claude_code/presentation/session_list_screen.dart';
import '../decision_proxy/presentation/trust_dashboard_screen.dart';
import '../notifications/presentation/inbox_screen.dart';
import '../queue/domain/queue_bloc.dart';
import '../queue/presentation/queue_dashboard_screen.dart';

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
