import 'package:flutter/material.dart';

const _kRetiredBannerYellow  = Color( 0xFFFFF3CD );
const _kRetiredBannerAccent  = Color( 0xFFFF9800 );

/// Retired 2026-05-05 — INTERACTIVE Claude Code controls (inject / interrupt /
/// end_session) were eliminated alongside the dispatch endpoint cluster.
/// Returns when parent's ClaudeCodeJob gains those methods.
///
/// Preserved as a banner-only screen so any leftover navigation surfaces the
/// retirement notice instead of crashing.
class ChatScreen extends StatelessWidget {
  const ChatScreen( { super.key } );

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( "Claude Code Chat (retired)" ) ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all( 24 ),
          child: Container(
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
                    "INTERACTIVE Claude Code chat retired 2026-05-05.\n\n"
                    "The dispatch / inject / interrupt / end_session endpoints "
                    "were eliminated in favor of the queue-submit path. "
                    "Returns when ClaudeCodeJob gains bidirectional control. "
                    "See parent retirement plan.",
                    style: TextStyle( fontStyle: FontStyle.italic ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
