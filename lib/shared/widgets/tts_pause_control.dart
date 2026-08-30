/// The shared speech-hold control (AC-S3.5c, plan 2026.08.29 §6).
///
/// PROMOTED from `focus_mode_screen.dart`, where `_PauseToggle` and
/// `_PausedBanner` were both `_`-private. Quick Ask could not import them,
/// so the obvious move was to write a third `StreamBuilder` over
/// `pausedStream` into a tree that already held two — which is the defect
/// AC-S3.5c exists to prevent, not a tidiness preference. Sam asked for
/// this promotion in the original cascade and nothing in the plan did it.
///
/// Behavior is asserted ONCE, in `test/widget/shared/pause_control_test.dart`.
/// A screen that mounts these asserts only that they are mounted — it does
/// not re-test them.
///
/// 🔴 **Both widgets seed from the synchronous [TtsOrchestrator.isPaused]
/// getter via `initialData`, and that is load-bearing** (AC-S3.5b).
/// `pausedStream` is a plain broadcast controller with no current-value
/// replay, so a control mounted while speech is ALREADY held would
/// otherwise receive nothing until the next transition and render "not
/// paused" indefinitely — over a queue that really is held. Store row
/// `a3fdb6ad` tracks fixing that in the stream's own contract; until it
/// lands, seeding here is what keeps every consumer honest.
library;

import 'package:flutter/material.dart';

import '../../services/tts/tts_orchestrator.dart';

/// Hold / resume toggle bound to [TtsOrchestrator.pausedStream].
///
/// A pause is a HOLD, not a mute (Q6): nothing is dropped, the in-flight
/// utterance finishes at its own boundary, and arrivals accumulate. Pair
/// it with a [TtsPausedBanner] so the held state is explained rather than
/// implied by an icon.
class TtsPauseToggle extends StatelessWidget {
  final TtsOrchestrator tts;

  /// The mounting screen's own test key, so focus mode and Quick Ask stay
  /// separately addressable while sharing one implementation.
  final Key? toggleKey;

  const TtsPauseToggle( { super.key, required this.tts, this.toggleKey } );

  @override
  Widget build( BuildContext context ) {
    return StreamBuilder<bool>(
      stream      : tts.pausedStream,
      initialData : tts.isPaused,     // AC-S3.5b — see the library note
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

/// Loudly-visible held state (Q6: held ≠ silent-forever) with the LIVE
/// held count off [TtsOrchestrator.queueDepthStream] — it ticks up as
/// messages accumulate under the hold, so held reads as *held*, not lost.
///
/// The Quick Ask half of AC-S3.5c: the hold is global, so a user who
/// paused on the focus screen arrives here to silence. Without this banner
/// they get a bare icon and no explanation of why nothing is speaking.
class TtsPausedBanner extends StatelessWidget {
  final TtsOrchestrator tts;

  /// The mounting screen's own test key.
  final Key? bannerKey;

  /// Optional extra context appended to the held-count line. Screens use
  /// it to say something true about their own surface; the orchestrator
  /// does not record WHERE a pause came from, so nothing here invents a
  /// provenance it cannot know.
  final String? reason;

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
      initialData : tts.isPaused,     // AC-S3.5b — see the library note
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
