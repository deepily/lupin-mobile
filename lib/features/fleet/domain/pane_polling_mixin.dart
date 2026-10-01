import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../../services/network/network_connectivity_service.dart';
import 'pane_visibility_mixin.dart';

/// Polls while the pane is visible and the app is foregrounded; one copy for every pane.
///
/// This is the timer half. The visibility machine (flags, lifecycle subscription, the
/// single in-flight request slot and its teardown) is in [PaneVisibilityMixin], which the
/// Live Console uses without a timer. What is left here is the periodic timer, the
/// metered interval and [pollOnce]. Order matters: declare it last, so [close] stops the
/// timer and then reaches the visibility teardown through `super.close()`.
///
/// ```dart
/// class XBloc extends Bloc<E, S> with PaneVisibilityMixin<E, S>, PanePollingMixin<E, S>
/// ```
///
/// The `on PaneVisibilityMixin<E, S>` clause makes the wrong order a compile error. The
/// host implements [pollOnce] and calls [startPolling] once it has a route to be visible
/// in. See [PaneVisibilityMixin] for the two obligations the host carries.
mixin PanePollingMixin<E, S> on PaneVisibilityMixin<E, S> {
  Timer? _timer;

  /// Performs one poll.
  ///
  /// The token is cancelled when the pane goes away mid-request. Pass it to the Dio call,
  /// or the cancellation has no effect.
  Future<void> pollOnce( CancelToken token );

  /// Wi-Fi, or any connection this phone does not pay by the megabyte for.
  static const Duration wifiInterval = Duration( seconds: 60 );

  /// Mobile data.
  static const Duration mobileInterval = Duration( seconds: 180 );

  /// Whether the connection is metered; a test seam.
  ///
  /// [NetworkConnectivityService] is a singleton and cannot be faked, and the interval
  /// needs one boolean from it, so tests override this getter instead.
  @protected
  bool get isMeteredConnection => NetworkConnectivityService().isMobile;

  /// How often to poll while visible and foregrounded: 60 s on Wi-Fi, 180 s on mobile data.
  ///
  /// A poll costs about 2.1 MB for 500 full rows, or 107 KB terse. At 60 s that is about
  /// 125 MB or 6.4 MB per foreground hour on one pane. So the panes pull terse and slow
  /// down on a metered connection. The interval is read when the timer is created, not on
  /// each tick. A change of network keeps the old period until the timer is rebuilt, on
  /// the next hide/show or background/foreground trip.
  Duration get pollInterval => isMeteredConnection ? mobileInterval : wifiInterval;

  /// True while the timer exists; tests assert this instead of counting requests.
  ///
  /// This is the timer, not the visibility flags. [PaneVisibilityMixin.isPaneActive]
  /// answers whether the pane should be working. The two differ for one synchronous
  /// moment after the pane becomes active.
  bool get isPolling => _timer != null;

  /// Begins observing visibility and polling; calling it twice starts one timer only.
  ///
  /// Alias for [PaneVisibilityMixin.startVisibility], named for what it means here.
  void startPolling() => startVisibility();

  /// Starts or stops the timer when the pane becomes active or inactive.
  ///
  /// When `active` is false the mixin has already cancelled the in-flight request, so
  /// only the timer is left to stop.
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

  // One guarded poll: a tick that lands while a poll is outstanding does nothing.
  // [PaneVisibilityMixin.claimRequest] is the guard for both ticks and transitions.
  void _fire() {
    final token = claimRequest();
    if ( token == null ) return;

    pollOnce( token ).whenComplete( () => releaseRequest( token ) ).ignore();
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    _timer = null;
    // Cancelling the timer does not cancel an outstanding HTTP request; the response would
    // still arrive and wake a backgrounded app. `PaneVisibilityMixin.close()` cancels the
    // request, and `super.close()` reaches it because this mixin is the most-derived.
    return super.close();
  }
}
