import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';

/// The Live Console — a read-only view of one Claude Code seat's transcript as it is
/// written (ruling Q9).
///
/// 🔴 THIS IS A PLACEHOLDER, ON PURPOSE, AND IT IS THE HONEST SHAPE FOR SLICE 2.
/// Slice 2 delivers the way IN — the roster read and the fleet-row button — and slice 3
/// delivers the stream. The alternative was to wire the button to nothing, or to a screen
/// that opens a socket against a server that does not emit yet: Mr. Radio's phase 1 has
/// not landed, so there is no `cc_transcript_append` emit site to receive from.
///
/// ⚠️ THE FOUR DEAD `queue_*_update` ARMS ARE WHY THIS IS SAID OUT LOUD. The app's
/// WebSocket dispatcher already carries four cases that have never fired, because no emit
/// site was ever built for them. §5's C9 names the rule that follows: the mobile
/// `cc_transcript_append` case lands only AFTER the server's emit site exists, and this
/// must not become a fifth. So this route deliberately opens no socket, sends no watch and
/// fetches no backlog — it states what it will be and shows the seat it was opened for,
/// which is enough for C5.9's tap arm to prove the button goes somewhere.
///
/// What slice 3 replaces this with, per §5:
///   - a route-scoped `TranscriptStreamBloc` in its own `BlocProvider` (C1), subscribing
///     to an app-root `TranscriptFrameRouter` for this one seat
///   - `GET /api/cc-transcript/{cc_session_id}?tail_bytes=65536` on open — the LAST 64 KB,
///     never `since_offset=0`, which would open the screen at the top of the transcript
///     (ruling Q6, A2.9)
///   - `cc_transcript_watch` from that response's `next_offset` and `file_epoch`
///   - a `ListView( reverse: true )` with the live end at the bottom (OSQ-9, ruled B),
///     markdown for prose and monospace `SelectableText` for everything else
///   - no input affordance of any kind (ruling Q8) — which is already true here, and
///     C5.5 asserts it
class LiveConsoleScreen extends StatelessWidget {
  /// The seat's full `stable_session_id` — §3's `cc_session_id`.
  ///
  /// ⚠️ THE FULL ID, NEVER THE 8-CHARACTER FORM. The roster join and the stream both key
  /// on this exact string at this exact width (§3), and the fleet row is the only entry
  /// point in v1 precisely because it is the only surface that has it (C-5).
  final String ccSessionId;

  /// What to call the seat on screen — its persona, or whatever the row showed.
  final String whoLabel;

  const LiveConsoleScreen( {
    super.key,
    required this.ccSessionId,
    required this.whoLabel,
  } );

  @override
  Widget build( BuildContext context ) {
    final theme = Theme.of( context );

    return Scaffold(
      key    : const Key( TestKeys.liveConsoleScreen ),
      appBar : AppBar( title: Text( "Console — $whoLabel" ) ),
      body   : Center(
        child: Padding(
          padding : const EdgeInsets.all( 24 ),
          child   : Column(
            mainAxisSize : MainAxisSize.min,
            children     : [
              Icon( Icons.terminal, size: 40, color: theme.hintColor ),
              const SizedBox( height: 12 ),
              Text(
                "Live console",
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox( height: 6 ),
              Text(
                "Streaming is not wired up yet. This screen will show "
                "$whoLabel's console as it is written.",
                textAlign : TextAlign.center,
                style     : theme.textTheme.bodySmall,
              ),
              const SizedBox( height: 12 ),
              // The id is on screen because it is the one fact that proves the button
              // opened the console for the RIGHT seat, and C5.9's tap arm reads it.
              // `SelectableText` so it can be copied into a DM, and monospace because it
              // is an identifier — the same treatment tool output gets in slice 3.
              SelectableText(
                ccSessionId,
                key       : const Key( TestKeys.liveConsoleSessionId ),
                textAlign : TextAlign.center,
                style     : theme.textTheme.bodySmall?.copyWith(
                  fontFamily : "monospace",
                  color      : theme.hintColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
