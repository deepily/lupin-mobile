import 'package:flutter/material.dart';

const _kRetiredBannerYellow  = Color( 0xFFFFF3CD );
const _kRetiredBannerAccent  = Color( 0xFFFF9800 );

/// A banner-only screen standing in for the retired interactive chat.
///
/// Interactive controls (inject, interrupt, end session) are not offered, so
/// any leftover navigation shows the retirement notice instead of crashing.
class ChatScreen extends StatelessWidget {
  /// Creates the screen.
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
