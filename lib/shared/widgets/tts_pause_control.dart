/// The shared speech-hold control: a toggle and a banner used by more than one screen.
///
/// Focus mode and Quick Ask both mount these, so one stream subscription serves both.
/// Their behaviour is asserted once, in `test/widget/shared/pause_control_test.dart`.
/// A screen that mounts them only asserts that they are mounted.
///
/// Both widgets seed from the synchronous [TtsOrchestrator.isPaused] getter through
/// `initialData`. The stream replays its current value one microtask after subscription.
/// Without the seed, the first frame would show the wrong state for speech already held.
library;

import 'package:flutter/material.dart';

import '../../services/tts/tts_orchestrator.dart';

/// Hold and resume toggle bound to [TtsOrchestrator.pausedStream].
///
/// A pause holds speech and does not mute it. Nothing is dropped, the utterance in flight
/// finishes at its own boundary, and new arrivals queue up.
/// Pair it with a [TtsPausedBanner] so the held state is explained and not only implied.
class TtsPauseToggle extends StatelessWidget {
  /// The orchestrator whose hold state the toggle shows and flips.
  final TtsOrchestrator tts;

  /// The mounting screen's own key, so each screen can address its own toggle.
  final Key? toggleKey;

  /// Creates a toggle for [tts].
  const TtsPauseToggle( { super.key, required this.tts, this.toggleKey } );

  @override
  Widget build( BuildContext context ) {
    return StreamBuilder<bool>(
      stream      : tts.pausedStream,
      initialData : tts.isPaused,     // Seeds the first frame; see the library note.
      builder: ( context, snap ) {
        final paused = snap.data ?? false;
        return IconButton(
          key       : toggleKey,
          tooltip   : paused ? 'Resume speech' : 'Hold speech',
          icon      : Icon( paused ? Icons.play_circle : Icons.pause_circle ),
          onPressed : () => paused ? tts.resume() : tts.pause(),
        );
      },
    );
  }
}

/// Banner that shows speech is held, with a live count of queued messages.
///
/// The count follows [TtsOrchestrator.queueDepthStream], so it grows as messages
/// accumulate under the hold and nothing looks lost.
/// The hold is global: a user who paused on one screen arrives at another in silence.
/// The banner explains why nothing is speaking.
class TtsPausedBanner extends StatelessWidget {
  /// The orchestrator whose hold state and queue depth the banner shows.
  final TtsOrchestrator tts;

  /// The mounting screen's own key.
  final Key? bannerKey;

  /// Optional extra context appended to the held-count line.
  ///
  /// Screens use it to say something true about their own surface. The orchestrator does
  /// not record where a pause came from, so the banner never claims a source.
  final String? reason;

  /// Creates a banner for [tts], with an optional [reason] line.
  const TtsPausedBanner( {
    super.key,
    required this.tts,
    this.bannerKey,
    this.reason,
  } );

  @override
  Widget build( BuildContext context ) {
    return StreamBuilder<bool>(
      stream      : tts.pausedStream,
      initialData : tts.isPaused,     // Seeds the first frame; see the library note.
      builder: ( context, pausedSnap ) {
        if ( pausedSnap.data != true ) return const SizedBox.shrink();
        return Material(
          key   : bannerKey,
          color : Theme.of( context ).colorScheme.tertiaryContainer,
          child : Padding(
            padding: const EdgeInsets.symmetric( horizontal: 12, vertical: 6 ),
            child: Row(
              children: [
                const Icon( Icons.pause, size: 16 ),
                const SizedBox( width: 8 ),
                Expanded(
                  child: StreamBuilder<int>(
                    stream      : tts.queueDepthStream,
                    initialData : tts.queueDepth,
                    builder: ( context, depthSnap ) => Text(
                      _line( depthSnap.data ?? 0 ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _line( int depth ) {
    final held = 'Speech held — $depth message(s) queued';
    final why  = ( reason ?? '' ).trim();
    return why.isEmpty ? held : '$held · $why';
  }
}
