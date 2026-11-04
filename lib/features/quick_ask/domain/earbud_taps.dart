import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'quick_ask_event.dart';
import 'quick_ask_state.dart';

/// A tap or a double tap on the earbud, after [EarbudTapReader] has told them apart.
enum EarbudGesture {
  /// One press, with no second press inside the window.
  single,
  /// A "next track" press, or two presses inside the window.
  double,
}

/// The tone that says what an earbud gesture did, since the phone may not be in view.
enum HandsFreeCue {
  /// Quick Ask has the earbuds.
  ///
  /// Playing it also makes this app the one Android sends the next earbud press to.
  ready,
  /// Recording started.
  started,
  /// Recording stopped.
  stopped,
  /// The transcript was sent.
  sent,
  /// The gesture did nothing: nothing to send, or recording is blocked.
  refused,
}

/// Turns raw earbud presses into [EarbudGesture]s.
///
/// Most earbuds send a double tap as a "next track" press, and that is a double at once.
/// Others send two play/pause presses, so a press waits [window] for a second one before it counts as a single.
/// A "previous track" press is ignored.
class EarbudTapReader {
  /// How long a press waits for a second press.
  static const Duration defaultWindow = Duration( milliseconds: 400 );

  /// Receives each gesture.
  final void Function( EarbudGesture ) onGesture;
  /// How long a press waits for a second press.
  final Duration window;
  Timer? _pending;

  /// Creates a reader that reports to [onGesture].
  EarbudTapReader( { required this.onGesture, this.window = defaultWindow } );

  /// Feeds one press.
  ///
  /// Ensures:
  ///   - a `next` press reports a double at once, and drops a press still waiting
  ///   - a second `media` press inside [window] reports one double and no single
  ///   - a lone `media` press reports a single after [window]
  void press( MediaButton button ) {
    switch ( button ) {
      case MediaButton.previous:
        return;
      case MediaButton.next:
        _pending?.cancel();
        _pending = null;
        onGesture( EarbudGesture.double );
      case MediaButton.media:
        final waiting = _pending;
        if ( waiting != null ) {
          waiting.cancel();
          _pending = null;
          onGesture( EarbudGesture.double );
          return;
        }
        _pending = Timer( window, () {
          _pending = null;
          onGesture( EarbudGesture.single );
        } );
    }
  }

  /// Drops a press still waiting, without reporting it.
  void dispose() {
    _pending?.cancel();
    _pending = null;
  }
}

/// What a gesture does in Quick Ask: the bloc event to send, if any, and the tone to play.
typedef EarbudAction = ( { QuickAskEvent? event, HandsFreeCue cue } );

/// Maps [gesture] to what it does, given the screen's [state].
///
/// It does what the on-screen buttons would do, and nothing they couldn't:
/// - a single tap is the record button: start when it's live, stop while recording
/// - a double tap is the send button; while recording it stops instead, so the question isn't lost
///
/// Ensures:
///   - `event` is null exactly when `cue` is [HandsFreeCue.refused]
///   - `cue` is never [HandsFreeCue.ready], which only the claim plays
EarbudAction earbudAction( EarbudGesture gesture, QuickAskState state ) {
  if ( state.phase == QuickAskPhase.recording || state.phase == QuickAskPhase.starting ) {
    return ( event: const QuickAskRecordReleased(), cue: HandsFreeCue.stopped );
  }
  switch ( gesture ) {
    case EarbudGesture.single:
      return state.canRecord
          ? ( event: const QuickAskRecordPressed(), cue: HandsFreeCue.started )
          : ( event: null, cue: HandsFreeCue.refused );
    case EarbudGesture.double:
      return state.hasDraft
          ? ( event: const QuickAskDraftSent(), cue: HandsFreeCue.sent )
          : ( event: null, cue: HandsFreeCue.refused );
  }
}
