import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../../services/network/network_connectivity_service.dart';
import 'pane_visibility_mixin.dart';

/// Lifecycle-aware, foreground-pane-only polling. ONE copy, mixed into each pane's
/// bloc — not five copies of a timer.
///
/// 🔴 THIS IS NOW THE TIMER HALF ONLY. The visibility machine — `_paneVisible`,
/// `_appForeground`, `_started`, the lifecycle subscription, the single in-flight request
/// slot and their teardown — lives in [PaneVisibilityMixin], because the Live Console
/// needs all of it and needs no timer at all: a WebSocket pushes to it. What is left here
/// is the `Timer.periodic`, the metered interval, and [pollOnce].
///
/// ⚠️ MIXIN ORDER IS LOAD-BEARING AND THE `on` CLAUSE IS WHAT ENFORCES IT:
///
/// ```dart
/// class XBloc extends Bloc<E, S> with PaneVisibilityMixin<E, S>, PanePollingMixin<E, S>
/// ```
///
/// This mixin declares `on PaneVisibilityMixin<E, S>`, so the wrong order does not
/// compile — a rule that cannot fail is not a rule. It goes **last** so it is the
/// most-derived: [close] stops the timer and then calls `super.close()`, which reaches
/// the visibility teardown.
///
/// "Poll only the foreground pane" is not a rule until something implements it, and this
/// app's architecture makes the wrong outcome the default — see [PaneVisibilityMixin]'s
/// header for the two obligations that fall on the host, and why a test of this feature
/// passes without it.
///
/// The host bloc implements [pollOnce] and calls [startPolling] once it has a route to be
/// visible in.
mixin PanePollingMixin<E, S> on PaneVisibilityMixin<E, S> {
  Timer? _timer;

  /// One poll. The token is cancelled when the pane goes away mid-request — honour it by
  /// handing it to the Dio call, or the cancellation buys nothing.
  Future<void> pollOnce( CancelToken token );

  /// Wi-Fi, or any connection this phone does not pay by the megabyte for.
  static const Duration wifiInterval = Duration( seconds: 60 );

  /// Mobile data. Plan §6.5's number.
  static const Duration mobileInterval = Duration( seconds: 180 );

  /// Test seam, and the same shape `lifecycleStream` uses for the same reason:
  /// `NetworkConnectivityService` is a hard singleton (`factory … => _instance`), so it
  /// cannot be faked. What the interval needs from it is one boolean, so that is what is
  /// injectable — not the service.
  @protected
  bool get isMeteredConnection => NetworkConnectivityService().isMobile;

  /// How often to poll while visible and foregrounded.
  ///
  /// ⚠️ SIXTY SECONDS IS THE WEB'S NUMBER AND A PHONE IS NOT A BROWSER TAB. Measured
  /// per poll: ~2.1 MB for 500 full rows, ~107 KB terse (`tasks.py:739`). At 60 s that
  /// is ~125 MB or ~6.4 MB per foreground hour on ONE pane. The panes pull terse, which
  /// is most of the difference; a pane on a metered connection also slows down —
  /// `network_connectivity_service.dart:52-53` exposes `isWifi`/`isMobile`.
  ///
  /// 🔴 THIS DEFAULT IS NOW NETWORK-AWARE, AND IT MOVED HERE FROM THE PANES BECAUSE IT
  /// WAS BECOMING A FOURTH COPY. Task List and Holding Area each carried a hand-written
  /// `_network.isMobile ? 180 : 60`, character for character; Fleet Status carried none
  /// and therefore polled every 60 s on mobile data (gap G8), and Finished Tasks did not
  /// poll at all (G7). Adding the line to the two panes that were missing it would have
  /// made four copies of one rule — and a rule copied four times is a rule that will
  /// disagree with itself, exactly as the two hand-written verb lists did.
  ///
  /// ⚠️ THE INTERVAL IS READ WHEN THE TIMER IS CREATED, NOT ON EVERY TICK, so a phone
  /// that moves from Wi-Fi to mobile data mid-poll keeps the faster period until the
  /// timer is next rebuilt — which happens on every hide/show and every background/
  /// foreground trip. That is pre-existing behaviour and is NOT changed here: reacting to
  /// the connectivity stream would restart the timer from a third trigger, which is a
  /// lifecycle change, and this row is not the place for one. Named rather than left for
  /// the next reader to discover.
  Duration get pollInterval => isMeteredConnection ? mobileInterval : wifiInterval;

  /// The poll predicate, exposed so a test can assert the state rather than infer it from
  /// request counts.
  ///
  /// ⚠️ THIS IS THE TIMER, NOT THE VISIBILITY FLAGS. `isPolling` was `_timer != null`
  /// before the extraction and stays `_timer != null` after it, so the four existing panes
  /// and their tests see no change. [PaneVisibilityMixin.isPaneActive] is the other
  /// question — *should* this pane be working — and the two are deliberately separate:
  /// a pane can be active with no timer yet for exactly one synchronous moment.
  bool get isPolling => _timer != null;

  /// Begin observing. Idempotent — a rebuild must not start a second timer.
  ///
  /// An alias for [PaneVisibilityMixin.startVisibility], kept because four panes and
  /// their tests call it by this name, and because "start polling" is what it means here.
  void startPolling() => startVisibility();

  /// The timer half of the visibility reaction.
  ///
  /// By the time this runs with `active: false`, the in-flight request has already been
  /// cancelled by the mixin — so all that is left is the timer, which is the thing that
  /// would otherwise keep firing.
  @override
  void onActiveChanged( { required bool active, required bool refreshNow } ) {
    if ( !active ) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic( pollInterval, ( _ ) => _fire() );
    if ( refreshNow ) _fire();
  }

  /// One guarded poll. A tick that lands while a poll is still outstanding does nothing —
  /// [PaneVisibilityMixin.claimRequest] is the guard, and it is the same guard whether
  /// the wake-up was a tick or a transition.
  void _fire() {
    final token = claimRequest();
    if ( token == null ) return;

    pollOnce( token ).whenComplete( () => releaseRequest( token ) ).ignore();
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _timer = null;
    // 🔴 CANCELLING A `Timer.periodic` DOES NOT CANCEL AN OUTSTANDING HTTP REQUEST.
    // The response still arrives, still parses, still wakes a backgrounded app. The
    // request half is cancelled by `PaneVisibilityMixin.close()`, which `super.close()`
    // reaches — which is why this mixin must be the most-derived one.
    return super.close();
  }
}
