import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/transcript_models.dart';

/// The one app-root object here; it hands WebSocket frames to the watching route's bloc.
///
/// The bloc is route-scoped, and the dispatcher can reach only app-root objects, so this
/// router is the seam the dispatcher can address. An app-root bloc would keep its server
/// watch open after the operator walked away. See the notes on the belts below.
class TranscriptFrameRouter {
  // The router is the first of two belts. The primary protection is server-side: frames go
  // only to watchers. If the server ever sent frames to every session of the user, the
  // phone's receive-all subscription would see other clients' watched seats, and
  // [publishAppend] dropping frames for seats with no open route makes that harmless. The
  // second belt is `websocket_subscription_manager.dart`. `WsBlocDispatcher.dispatch`
  // resolves its targets through `ServiceLocator.get<XBloc>()`, which returns singletons
  // that outlive their routes, so the bloc itself cannot go there. The drop needs a test
  // that can fail, so [droppedFrames] is a counter: "nothing happened" cannot be asserted
  // directly, and a silent drop looks like a router never called.
  //
  // One broadcast controller per watched seat, keyed by `cc_session_id` and created lazily
  // on the first [appendsFor]. A single-subscription stream would throw on a second
  // listener, and a route re-entered before its predecessor's `cancel()` settles is exactly
  // that.
  final Map<String, StreamController<TranscriptAppend>> _appends = {};
  final Map<String, StreamController<TranscriptStateFrame>> _states = {};

  // Fires once per `auth_success`, for every open console. The reconnect signal comes
  // through the router because the bloc is route-scoped and the dispatcher cannot reach it:
  // the dispatcher tells the router, which is app-root, and whichever console is open hears
  // it. A closed console has no listener and the signal costs nothing.
  final StreamController<void> _reconnects = StreamController<void>.broadcast();

  /// Fires on each successful reconnection; subscribe on route open and cancel on close.
  Stream<void> get reconnects => _reconnects.stream;

  /// Called by the dispatcher on `auth_success`, which every successful reconnection
  /// completes.
  ///
  /// If the seat cleared while the phone was away, the re-watch names a stale epoch and the
  /// server answers `epoch_mismatch` instead of rebasing.
  void publishReconnected() {
    if ( _reconnects.isClosed ) return;
    _reconnects.add( null );
  }

  /// How many frames arrived for a seat nobody is watching.
  ///
  /// It is the belt's receipt, not diagnostics: a test asserts that it moves.
  int droppedFrames = 0;

  /// The frames for one seat. Subscribe on route open, cancel on close.
  ///
  /// Ensures:
  ///     - the same stream for the same id, so two subscribers see the same frames
  ///     - a stream exists from the first call, so a frame arriving between subscribe and
  ///       the first watch acknowledgement is not lost to a missing controller
  Stream<TranscriptAppend> appendsFor( String ccSessionId ) =>
      _appends.putIfAbsent(
        ccSessionId,
        () => StreamController<TranscriptAppend>.broadcast(),
      ).stream;

  /// The state frames for one seat; subscribe on route open, cancel on close.
  Stream<TranscriptStateFrame> statesFor( String ccSessionId ) =>
      _states.putIfAbsent(
        ccSessionId,
        () => StreamController<TranscriptStateFrame>.broadcast(),
      ).stream;

  /// True when some route is currently listening for this seat.
  bool isWatched( String ccSessionId ) {
    final appends = _appends[ ccSessionId ];
    final states  = _states[ ccSessionId ];
    return ( appends != null && appends.hasListener ) ||
           ( states  != null && states.hasListener );
  }

  /// Routes one `cc_transcript_append` frame.
  ///
  /// Ensures:
  ///     - delivered only to a seat with a live listener
  ///     - otherwise counted in [droppedFrames] and discarded
  ///     - a frame with no `cc_session_id` is dropped. It cannot be routed, and guessing
  ///       "the only open console" would put another seat's output under this seat's
  ///       heading, which this surface must never do
  void publishAppend( TranscriptAppend frame ) {
    final id = frame.ccSessionId;
    if ( id == null ) {
      droppedFrames++;
      debugPrint( '[Transcript] append with no cc_session_id — dropped' );
      return;
    }
    _publish( _appends[ id ], frame, id, "append" );
  }

  /// Routes one `cc_transcript_state` frame; dropped and counted like [publishAppend].
  void publishState( TranscriptStateFrame frame ) {
    final id = frame.ccSessionId;
    if ( id == null ) {
      droppedFrames++;
      debugPrint( '[Transcript] state with no cc_session_id — dropped' );
      return;
    }
    _publish( _states[ id ], frame, id, "state" );
  }

  void _publish<T>( StreamController<T>? controller, T frame, String id, String what ) {
    if ( controller == null || !controller.hasListener ) {
      droppedFrames++;
      debugPrint( '[Transcript] $what for unwatched seat $id — dropped' );
      return;
    }
    controller.add( frame );
  }

  /// Releases a seat's controllers once its route is gone.
  ///
  /// The bloc's `close()` calls this, not the router, because the router cannot know when a
  /// subscription is the last one. Without it `_appends` would grow by one entry per console
  /// ever opened, unbounded on an object that lives as long as the app.
  void release( String ccSessionId ) {
    _appends.remove( ccSessionId )?.close();
    _states.remove( ccSessionId )?.close();
  }

  /// Closes every controller; for tests and for app teardown.
  void dispose() {
    for ( final c in _appends.values ) { c.close(); }
    for ( final c in _states.values ) { c.close(); }
    _appends.clear();
    _states.clear();
    _reconnects.close();
  }
}
