import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/lifecycle/app_lifecycle_service.dart';

/// The visibility machine, with no timer in it: *is this surface on screen, and is the
/// app in front of the user?* — plus the single in-flight request slot, and one hook the
/// host implements to act on the answer.
///
/// 🔴 THIS IS AN EXTRACTION, NOT A NEW RULE. Every flag, transition and comment below
/// came out of `PanePollingMixin` unchanged; what is new is that the *reaction* is a hook
/// instead of a `Timer`. The four polling panes get their timer back by mixing
/// `PanePollingMixin` in on top of this one, and the Live Console — which has no timer at
/// all, because a WebSocket pushes to it — mixes in this half alone.
///
/// ⚠️ THE STATE IS THREE FLAGS, NOT ONE, and [startVisibility] deliberately does NOT
/// begin work. It subscribes to [lifecycleStream] and nothing else; the host is not
/// active until a route also says [onPaneVisible]. That split is load-bearing: a bloc
/// built by a `BlocProvider` is alive before its route is on screen, and a host that
/// started work at construction would work while invisible.
///
/// ⇒ Two things are therefore required of the host, and neither is optional:
///   1. The host bloc is **route-scoped**, not an app-root singleton. `lib/app.dart`
///      registers nine `BlocProvider`s at the app root (`:265-300`), each a
///      `ServiceLocator` singleton, so a bloc registered that way outlives its route.
///      None of the four pane blocs is among the nine, and the Live Console must not
///      become the first — an app-root console keeps its watch open after its route pops,
///      and the obvious test, *"the console stops when you leave it"*, PASSES ANYWAY.
///      A test that passes without the feature is worse than no test.
///   2. The route tells the bloc when it is on screen, via [onPaneVisible] /
///      [onPaneHidden]. The guarding test is: *with pane A on screen, pane B issues
///      zero requests.*
///
/// Mixin order matters when both halves are used, and the `on` clause is what makes it
/// a rule rather than a comment:
///
/// ```dart
/// class XBloc extends Bloc<E, S> with PaneVisibilityMixin<E, S>, PanePollingMixin<E, S>
/// ```
///
/// `PanePollingMixin` declares `on PaneVisibilityMixin<E, S>`, so the wrong order does
/// not compile. It must be **last** so it is the most-derived: its `close()` stops its
/// timer and then calls `super.close()`, which reaches this mixin's teardown.
mixin PaneVisibilityMixin<E, S> on Bloc<E, S> {
  /// The one request allowed to be outstanding at a time. Owned here rather than in the
  /// timer half, because "cancel the request when the surface goes away" is a visibility
  /// rule and every host needs it.
  CancelToken? _inFlight;

  StreamSubscription<AppLifecycleState>? _lifecycleSub;

  bool _paneVisible   = false;
  bool _appForeground = true;
  bool _started       = false;

  /// The host's one hook. [_reconcile] calls it on **every** transition, active or not.
  ///
  /// Requires:
  ///   - the host is mixed in on a `Bloc` and has not been closed
  ///
  /// Ensures:
  ///   - `active` is true only when the pane is on screen AND the app is foregrounded
  ///   - `refreshNow` is true only when the host should do work *now*: on pane-visible,
  ///     and on a return from the background. It is never true when `active` is false
  ///   - by the time the hook is called with `active: false`, any outstanding request has
  ///     already been cancelled and the in-flight slot is empty. The host's job on that
  ///     arm is to stop its **own** machinery — a timer, a subscription, a server-side
  ///     watch — not the request
  ///
  /// ⚠️ THERE IS NO `CancelToken` ARGUMENT, DELIBERATELY. A periodic tick is not a
  /// transition, so a token handed out at the last transition would have to serve every
  /// tick after it — which breaks the one-at-a-time guard and makes a hide-cancel cancel
  /// a token already spent on N requests. The host mints one per request through
  /// [claimRequest] instead, whatever woke it. (Pocholo N1; ruled by Tiffany 2026-09-27.)
  @protected
  void onActiveChanged( { required bool active, required bool refreshNow } );

  /// Test seam. Defaults to the app-wide lifecycle service, which is a hard singleton
  /// (`AppLifecycleService._internal()`) and therefore cannot be faked — so the stream is
  /// injectable instead of the service.
  @protected
  Stream<AppLifecycleState> get lifecycleStream => AppLifecycleService().lifecycleStream;

  /// True only when this surface is on screen AND the app is foregrounded. Exposed so a
  /// test can assert the state rather than infer it from request counts.
  bool get isPaneActive => _paneVisible && _appForeground;

  /// The outstanding request's token, or null. Read-only: [claimRequest] and
  /// [releaseRequest] are the only ways to move it.
  @protected
  CancelToken? get inFlightToken => _inFlight;

  /// Begin observing. Idempotent — a rebuild must not subscribe twice.
  ///
  /// ⚠️ THIS DOES NOT START WORK. It is `PanePollingMixin.startPolling()`'s old body,
  /// verbatim: a lifecycle subscription and nothing else.
  void startVisibility() {
    if ( _started ) return;
    _started = true;
    _lifecycleSub = lifecycleStream.listen( _onLifecycle );
  }

  /// The route says this surface is on screen.
  void onPaneVisible() {
    if ( _paneVisible ) return;
    _paneVisible = true;
    _reconcile( refreshNow: true );
  }

  /// The route says this surface is no longer on screen.
  void onPaneHidden() {
    if ( !_paneVisible ) return;
    _paneVisible = false;
    _reconcile();
  }

  /// Take the in-flight slot for one request.
  ///
  /// Every request goes through here, whatever woke it — a timer tick, a pane becoming
  /// visible, a return from the background, a catch-up after a reconnect.
  ///
  /// Requires:
  ///   - the host will pass the returned token to the call it is about to make, and will
  ///     [releaseRequest] it when that call settles
  ///
  /// Ensures:
  ///   - returns null when a request is already outstanding and not cancelled, in which
  ///     case the host does nothing
  ///   - otherwise returns a **fresh** token, now held as the in-flight one
  @protected
  CancelToken? claimRequest() {
    // One request at a time. A request landing on a slow predecessor would queue work
    // behind a connection that is already struggling.
    if ( _inFlight != null && !_inFlight!.isCancelled ) return null;

    final token = CancelToken();
    _inFlight = token;
    return token;
  }

  /// Release the in-flight slot, if [token] is still the one holding it.
  ///
  /// The identity check matters: a token cancelled by [onPaneHidden] is replaced in the
  /// slot before its own request finishes, and the late `whenComplete` must not clear its
  /// successor.
  @protected
  void releaseRequest( CancelToken token ) {
    if ( identical( _inFlight, token ) ) _inFlight = null;
  }

  /// 🔴 FIVE STATES, NOT ONE. `app_lifecycle_service.dart:103-116` already switches on
  /// all five and the pre-cascade plan named only `paused`.
  ///
  /// Flutter delivers `inactive` for transient interruptions — a notification-shade pull,
  /// an incoming-call banner — and on Android `hidden` precedes `paused`. Stopping only
  /// on `paused` stops TOO LATE; stopping on `inactive` to be safe THRASHES the work
  /// every time the shade is pulled. `detached` went unmentioned entirely.
  ///
  /// ⇒ `resumed` is the only foreground state. Everything else goes inactive, and
  /// **every** non-`resumed` state earns a refresh on the way back.
  ///
  /// 🔴 THAT SENTENCE USED TO CLAIM THE OPPOSITE, AND THE CODE NEVER DID IT. It read:
  /// *"`inactive` is treated as a stop WITHOUT a resume-refresh, so a shade pull costs one
  /// paused timer rather than a fresh request on the way back."* The code cannot tell
  /// `inactive` from `paused`, `hidden` or `detached` — all four set `_appForeground`
  /// false, so any of them followed by `resumed` gives `wasForeground == false` and
  /// therefore `refreshNow: true`. Either the optimisation was lost in a refactor or it
  /// was never written. Found by María 🌸 2026-09-22, reading the code against the comment
  /// while reviewing a plan that had reasoned from the comment and got the conclusion
  /// wrong. **Corrected to describe what this code actually does.**
  ///
  /// ⚠️ AND THE BEHAVIOUR IS PROBABLY RIGHT, WHICH IS WHY ONLY THE COMMENT CHANGED.
  /// María's recommendation, recorded here as a recommendation and not as settled design
  /// (row `de509b51`, open for Rick): a shade pull that returns the operator to **stale
  /// data** is worse than one extra request, because the moment they come back is exactly
  /// the moment they are looking at the pane. On that reading the withdrawn optimisation
  /// was never justified — nobody ever measured a cost for the refresh it removed — so the
  /// refresh on return is **wanted**, not merely tolerated. If someone does measure a real
  /// battery cost, implementing it is a behaviour change across every host of this mixin,
  /// and needs its own ruling.
  ///
  /// ⚠️ THE BLAST RADIUS OF THAT OPEN ROW GREW WITH THIS EXTRACTION, AND THE ROW HAS NOT
  /// BEEN RE-SCOPED. `de509b51` was written as scoped to "the three panes that mix this
  /// in". Every host of this mixin now inherits whatever it decides — the Live Console
  /// included, where a return from the background is a REST catch-up plus a re-watch
  /// rather than one poll.
  void _onLifecycle( AppLifecycleState state ) {
    final wasForeground = _appForeground;
    _appForeground = state == AppLifecycleState.resumed;

    if ( !_appForeground ) {
      _reconcile();
      return;
    }
    // Returning to the foreground refreshes once — the data is as stale as the time
    // spent away, and a user who just came back is looking at it.
    _reconcile( refreshNow: !wasForeground );
  }

  /// The one reader of the three flags, and the only caller of [onActiveChanged].
  void _reconcile( { bool refreshNow = false } ) {
    if ( !isPaneActive ) {
      // 🔴 STOPPING THE HOST'S MACHINERY IS NOT THE SAME AS CANCELLING THE REQUEST.
      // Cancelling a `Timer.periodic` does not cancel an outstanding HTTP call: the
      // response still arrives, still parses, still wakes a backgrounded app — which is
      // exactly the wake-up the whole rule exists to prevent, and with a
      // multi-hundred-KB body behind it. This half is the mixin's; the timer, the
      // subscription or the server-side watch is the host's, on the `active: false` arm.
      cancelInFlight( 'pane hidden or app backgrounded' );
      onActiveChanged( active: false, refreshNow: false );
      return;
    }
    onActiveChanged( active: true, refreshNow: refreshNow );
  }

  /// Cancel and release whatever is in the in-flight slot. A no-op when it is empty or
  /// already cancelled, so it is safe to call twice.
  @protected
  void cancelInFlight( String reason ) {
    final token = _inFlight;
    _inFlight = null;

    if ( token != null && !token.isCancelled ) token.cancel( reason );
  }

  @override
  Future<void> close() {
    cancelInFlight( 'bloc closed' );
    _lifecycleSub?.cancel();
    _lifecycleSub = null;
    _started = false;
    return super.close();
  }
}
