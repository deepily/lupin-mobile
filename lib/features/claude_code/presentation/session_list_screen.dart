import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/presentation/queue_dashboard_screen.dart';
import '../domain/claude_code_bloc.dart';
import 'dispatch_sheet.dart';

const _kRetiredBannerYellow  = Color( 0xFFFFF3CD );
const _kRetiredBannerAccent  = Color( 0xFFFF9800 );

/// Retired 2026-05-05 — INTERACTIVE Claude Code session list was eliminated
/// alongside the dispatch endpoint cluster. BOUNDED submissions land as `cc-*`
/// jobs in the Queue Dashboard (Tier 3 surface).
///
/// Preserved as a banner + CTA so the home-tab entry surfaces the retirement
/// notice and the live successor surface.
class SessionListScreen extends StatelessWidget {
  const SessionListScreen( { super.key } );

  void _openDispatch( BuildContext context ) {
    showModalBottomSheet<void>(
      context            : context,
      isScrollControlled : true,
      builder            : ( _ ) => BlocProvider.value(
        value : context.read<ClaudeCodeBloc>(),
        child : const DispatchSheet(),
      ),
    );
  }

  void _openQueueDashboard( BuildContext context ) {
    Navigator.of( context ).push( MaterialPageRoute(
      builder: ( _ ) => const QueueDashboardScreen(),
    ) );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( "Claude Code (retired)" ) ),
      floatingActionButton: FloatingActionButton(
        onPressed : () => _openDispatch( context ),
        tooltip   : "New BOUNDED submission",
        child     : const Icon( Icons.add ),
      ),
      body: Padding(
        padding: const EdgeInsets.all( 16 ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: const BoxDecoration(
                color  : _kRetiredBannerYellow,
                border : Border( left: BorderSide( color: _kRetiredBannerAccent, width: 4 ) ),
              ),
              padding: const EdgeInsets.all( 16 ),
              child: Row(
                children: [
                  const Icon( Icons.warning_amber_rounded, color: _kRetiredBannerAccent, size: 32 ),
                  const SizedBox( width: 16 ),
                  const Expanded(
                    child: Text(
                      "INTERACTIVE Claude Code session list retired 2026-05-05.\n\n"
                      "BOUNDED submissions still work via the + button and land as `cc-*` jobs "
                      "in the Queue Dashboard. INTERACTIVE controls return when ClaudeCodeJob "
                      "gains inject / interrupt / end_session.",
                      style: TextStyle( fontStyle: FontStyle.italic ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox( height: 24 ),
            FilledButton.tonal(
              onPressed : () => _openQueueDashboard( context ),
              child     : const Padding(
                padding: EdgeInsets.symmetric( vertical: 12 ),
                child: Text( "View Claude Code jobs in Queue dashboard" ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
