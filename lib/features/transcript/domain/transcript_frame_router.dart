import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/transcript_models.dart';

/// The one app-root object in this feature: it takes frames off the WebSocket dispatcher and
/// hands them to whichever route-scoped bloc is watching that seat, if any.
///
/// 🔴 THIS EXISTS BECAUSE THE BLOC MUST **NOT** BE APP-ROOT, AND THE DISPATCHER CAN ONLY
/// REACH APP-ROOT THINGS. `WsBlocDispatcher.dispatch` resolves its targets through
/// `ServiceLocator.get<XBloc>()`, which returns singletons that outlive their routes (C1).
/// A `TranscriptStreamBloc` registered that way would keep its server-side watch open after
/// the operator walked away — and the obvious test, *"the console stops when you leave
/// it"*, PASSES ANYWAY, because nothing on screen is asking. So the bloc is route-scoped in
/// its own `BlocProvider`, and this router is the app-root seam the dispatcher can address.
///
/// ⚠️ IT IS ALSO THE FIRST OF §5's TWO BELTS (C6). The primary mitigation is server-side —
/// frames go only to watchers (§3) — but that rests on §2 carrying the stream over
/// `emit_to_session`. If A-T2 ever resolves to `emit_to_user` instead, the phone's
/// receive-all subscription (`websocket_service.dart:210`, `'subscribed_events': []`) would
/// see other clients' watched seats. [publishAppend] dropping frames for seats with no open
/// route is what makes that harmless here. The second belt is
/// `websocket_subscription_manager.dart`, and nothing new gets built for it.
///
/// 🔴 AND "DROPS FRAMES FOR A SEAT WITH NO LISTENER" IS A PROPERTY THAT NEEDS A TEST THAT
/// CAN FAIL. C5.11's negative control is to register the bloc app-root and watch the test
/// go red. Here the observable is [droppedFrames]: a counter, because "nothing happened" is
/// not something a test can assert on directly, and a silent drop is indistinguishable from
/// a router that was never called at all.
class TranscriptFrameRouter {
  /// One broadcast controller per watched seat, keyed by `cc_session_id`.
  ///
  /// ⚠️ BROADCAST, NOT SINGLE-SUBSCRIPTION, and created lazily on the first [appendsFor].
  /// A single-subscription stream would throw on a second listener, and a route re-entered
  /// before its predecessor's `cancel()` has settled is exactly that.
  final Map<String, StreamController<TranscriptAppend>> _appends = {};
  final Map<String, StreamController<TranscriptStateFrame>> _states = {};

  /// Frames that arrived for a seat nobody is watching.
  ///
  /// This is the belt's receipt. It is not diagnostics: C5.11 asserts it moves.
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

  /// Route one `cc_transcript_append` frame.
  ///
  /// Ensures:
  ///     - delivered only to a seat with a live listener
  ///     - otherwise counted in [droppedFrames] and discarded
  ///     - a frame with no `cc_session_id` is dropped: it cannot be routed, and guessing
  ///       "the only open console" would deliver another seat's output under this seat's
  ///       heading — the one failure this surface must never have
  void publishAppend( TranscriptAppend frame ) {
    final id = frame.ccSessionId;
    if ( id == null ) {
      droppedFrames++;
      debugPrint( '[Transcript] append with no cc_session_id — dropped' );
      return;
    }
    _publish( _appends[ id ], frame, id, "append" );
  }

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

  /// Release a seat's controllers once its route is gone.
  ///
  /// ⚠️ CALLED BY THE BLOC'S `close()`, NOT BY THE ROUTER ITSELF. The router cannot know
  /// when a subscription is the last one; the bloc knows when it is closing. Without this,
  /// `_appends` grows by one entry per console ever opened — small, but unbounded, and this
  /// object lives as long as the app does.
  void release( String ccSessionId ) {
    _appends.remove( ccSessionId )?.close();
    _states.remove( ccSessionId )?.close();
  }

  /// For tests and for app teardown.
  void dispose() {
    for ( final c in _appends.values ) { c.close(); }
    for ( final c in _states.values ) { c.close(); }
    _appends.clear();
    _states.clear();
  }
}
