import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/lifecycle/app_lifecycle_service.dart';

/// Lifecycle-aware, foreground-pane-only polling. ONE copy, mixed into each pane's
/// bloc — not five copies of a timer.
///
/// 🔴 "POLL ONLY THE FOREGROUND PANE" IS NOT A RULE UNTIL SOMETHING IMPLEMENTS IT, AND
/// THIS APP'S ARCHITECTURE MAKES THE WRONG OUTCOME THE DEFAULT. `app.dart:248-278`
/// registers seven `BlocProvider`s at the APP ROOT, each a `ServiceLocator` singleton,
/// so a pane's bloc outlives its route. Five panes following that pattern means five
/// timers running whichever destination is showing — and the obvious test,
/// *"polling stops when backgrounded and refreshes once on resume"*, PASSES WITH ALL
/// FIVE RUNNING. A test that passes without the feature is worse than no test.
///
/// ⇒ Two things are therefore required, and neither is optional:
///   1. The pane blocs are **route-scoped**, not app-root singletons. That is a
///      deliberate departure from this app's convention and Rick should see it as a
///      decision rather than discover it as a surprise.
///   2. The route tells the bloc when it is on screen, via [onPaneVisible] /
///      [onPaneHidden]. The guarding test is: *with pane A on screen, pane B issues
///      zero requests.*
///
/// The host bloc implements [pollOnce] and calls [startPolling] once it has a route to
/// be visible in.
mixin PanePollingMixin<E, S> on Bloc<E, S> {
  Timer?          _timer;
  CancelToken?    _inFlight;
  StreamSubscription<AppLifecycleState>? _lifecycleSub;

  bool _paneVisible  = false;
  bool _appForeground = true;
  bool _started      = false;

  /// One poll. The token is cancelled when the pane goes away mid-request — honour it
  /// by handing it to the Dio call, or the cancellation buys nothing.
  Future<void> pollOnce( CancelToken token );

  /// How often to poll while visible and foregrounded.
  ///
  /// ⚠️ SIXTY SECONDS IS THE WEB'S NUMBER AND A PHONE IS NOT A BROWSER TAB. Measured
  /// per poll: ~2.1 MB for 500 full rows, ~107 KB terse (`tasks.py:739`). At 60 s that
  /// is ~125 MB or ~6.4 MB per foreground hour on ONE pane. The panes pull terse, which
  /// is most of the difference; a pane on a metered connection should also slow down —
  /// `network_connectivity_service.dart:52-53` already exposes `isWifi`/`isMobile`.
  /// Override this to read it.
  Duration get pollInterval => const Duration( seconds: 60 );

  /// Test seam. Defaults to the app-wide lifecycle service, which is a hard singleton
  /// (`AppLifecycleService._instance`) and therefore cannot be faked — so the stream is
  /// injectable instead of the service.
  @protected
  Stream<AppLifecycleState> get lifecycleStream => AppLifecycleService().lifecycleStream;

  /// True only when this pane is on screen AND the app is foregrounded. The poll
  /// predicate, exposed so a test can assert the state rather than infer it from
  /// request counts.
  bool get isPolling => _timer != null;

  /// Begin observing. Idempotent — a rebuild must not start a second timer.
  void startPolling() {
    if ( _started ) return;
    _started = true;
    _lifecycleSub = lifecycleStream.listen( _onLifecycle );
  }

  /// The route says this pane is on screen.
  void onPaneVisible() {
    if ( _paneVisible ) return;
    _paneVisible = true;
    _reconcile( refreshNow: true );
  }

  /// The route says this pane is no longer on screen.
  void onPaneHidden() {
    if ( !_paneVisible ) return;
    _paneVisible = false;
    _reconcile();
  }

  /// 🔴 FIVE STATES, NOT ONE. `app_lifecycle_service.dart:103-116` already switches on
  /// all five and the pre-cascade plan named only `paused`.
  ///
  /// Flutter delivers `inactive` for transient interruptions — a notification-shade pull,
  /// an incoming-call banner — and on Android `hidden` precedes `paused`. Stopping only
  /// on `paused` stops TOO LATE; stopping on `inactive` to be safe THRASHES the timer
  /// every time the shade is pulled. `detached` went unmentioned entirely.
  ///
  /// ⇒ `resumed` is the only foreground state. Everything else stops the timer, and
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
  /// battery cost, implementing it is a behaviour change across the three panes that mix
  /// this in, and needs its own ruling.
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

  void _reconcile( { bool refreshNow = false } ) {
    final shouldPoll = _paneVisible && _appForeground;

    if ( !shouldPoll ) {
      _stopTimerAndRequest();
      return;
    }
    _timer ??= Timer.periodic( pollInterval, ( _ ) => _fire() );
    if ( refreshNow ) _fire();
  }

  void _fire() {
    // One request at a time. A poll landing on a slow predecessor would queue requests
    // behind a connection that is already struggling.
    if ( _inFlight != null && !_inFlight!.isCancelled ) return;

    final token = CancelToken();
    _inFlight = token;
    pollOnce( token ).whenComplete( () {
      if ( identical( _inFlight, token ) ) _inFlight = null;
    } ).ignore();
  }

  /// 🔴 CANCELLING A `Timer.periodic` DOES NOT CANCEL AN OUTSTANDING HTTP REQUEST.
  /// The response still arrives, still parses, still wakes a backgrounded app — which is
  /// exactly the wake-up the whole rule exists to prevent, and with a multi-hundred-KB
  /// body behind it. The timer and the request are two separate things to stop.
  void _stopTimerAndRequest() {
    _timer?.cancel();
    _timer = null;

    final token = _inFlight;
    _inFlight = null;
    if ( token != null && !token.isCancelled ) {
      token.cancel( 'pane hidden or app backgrounded' );
    }
  }

  @override
  Future<void> close() {
    _stopTimerAndRequest();
    _lifecycleSub?.cancel();
    _lifecycleSub = null;
    _started = false;
    return super.close();
  }
}
