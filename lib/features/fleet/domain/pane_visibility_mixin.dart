import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/lifecycle/app_lifecycle_service.dart';

/// Tracks whether a surface is on screen and the app is in front, with no timer.
///
/// It also owns the single in-flight request slot and one hook, [onActiveChanged], that
/// the host implements. [PanePollingMixin] adds a timer on top. The Live Console uses
/// this half alone, because a WebSocket pushes to it.
///
/// [startVisibility] only subscribes to [lifecycleStream]. The host is not active until a
/// route calls [onPaneVisible], because a bloc built by a `BlocProvider` exists before its
/// route is on screen. The host must meet two obligations:
///   - Be route-scoped, not an app-root singleton. A bloc registered at the app root
///     outlives its route and keeps working after the route pops, and a test of "stops
///     when you leave" can still pass. `lib/app.dart` registers the app-root providers.
///   - Have the route call [onPaneVisible] and [onPaneHidden]. The guarding test is:
///     with pane A on screen, pane B issues zero requests.
///
/// When both halves are used, mix this one in first and [PanePollingMixin] last, so its
/// `close()` stops the timer and then reaches this teardown. The `on` clause enforces it.
mixin PaneVisibilityMixin<E, S> on Bloc<E, S> {
  // The one request allowed to be outstanding. It lives here, not in the timer half,
  // because cancelling the request when the surface goes away is a visibility rule.
  CancelToken? _inFlight;

  StreamSubscription<AppLifecycleState>? _lifecycleSub;

  bool _paneVisible   = false;
  bool _appForeground = true;
  bool _started       = false;

  /// The host's hook, called by `_reconcile` on every transition, active or not.
  ///
  /// There is no `CancelToken` argument. A periodic tick is not a transition, so one
  /// token would serve every tick and break the one-at-a-time guard. The host mints a
  /// token per request through [claimRequest].
  ///
  /// Requires:
  ///   - the host is mixed in on a `Bloc` and has not been closed
  ///
  /// Ensures:
  ///   - `active` is true only when the pane is on screen and the app is foregrounded
  ///   - `refreshNow` is true only on pane-visible and on a return from the background
  ///   - `refreshNow` is never true when `active` is false
  ///   - with `active: false`, any outstanding request is already cancelled and the slot
  ///     is empty; the host stops its own timer, subscription or server-side watch
  @protected
  void onActiveChanged( { required bool active, required bool refreshNow } );

  /// The app lifecycle stream; a test seam.
  ///
  /// [AppLifecycleService] is a singleton and cannot be faked, so the stream is
  /// injectable instead of the service.
  @protected
  Stream<AppLifecycleState> get lifecycleStream => AppLifecycleService().lifecycleStream;

  /// True only when this surface is on screen and the app is foregrounded.
  ///
  /// Exposed so a test can assert the state instead of counting requests.
  bool get isPaneActive => _paneVisible && _appForeground;

  /// The outstanding request's token, or null.
  ///
  /// Only [claimRequest] and [releaseRequest] change it.
  @visibleForTesting
  CancelToken? get inFlightToken => _inFlight;

  /// Begins observing the app lifecycle; calling it twice subscribes once.
  ///
  /// This does not start work; the host stays inactive until [onPaneVisible].
  void startVisibility() {
    if ( _started ) return;
    _started = true;
    _lifecycleSub = lifecycleStream.listen( _onLifecycle );
  }

  /// The route says this surface is on screen; triggers a refresh.
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

  /// Takes the in-flight slot for one request.
  ///
  /// Every request goes through here, whatever woke it. That covers a timer tick, a pane
  /// becoming visible, a return from the background and a catch-up after a reconnect.
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
    // One request at a time: a second would queue behind a connection that is struggling.
    if ( _inFlight != null && !_inFlight!.isCancelled ) return null;

    final token = CancelToken();
    _inFlight = token;
    return token;
  }

  /// Releases the in-flight slot if [token] still holds it.
  ///
  /// The identity check is needed. A token cancelled by [onPaneHidden] is replaced in the
  /// slot before its request finishes. Its late `whenComplete` must not clear the
  /// successor.
  @protected
  void releaseRequest( CancelToken token ) {
    if ( identical( _inFlight, token ) ) _inFlight = null;
  }

  // Reacts to the five lifecycle states. Only `resumed` is foreground; the other four
  // (`inactive`, `hidden`, `paused`, `detached`) all set the app inactive. Returning from
  // any of them to `resumed` refreshes once. Flutter sends `inactive` for transient
  // interruptions such as a notification-shade pull, and on Android `hidden` precedes
  // `paused`; the code cannot tell them apart, so a shade pull also earns a refresh.
  // That is wanted: returning to stale data is worse than one extra request. Changing it
  // alters every host of this mixin, the Live Console included, and needs its own ruling.
  void _onLifecycle( AppLifecycleState state ) {
    final wasForeground = _appForeground;
    _appForeground = state == AppLifecycleState.resumed;

    if ( !_appForeground ) {
      _reconcile();
      return;
    }
    // Returning to the foreground refreshes once: the data is as stale as the time spent
    // away, and the user who just came back is looking at it.
    _reconcile( refreshNow: !wasForeground );
  }

  // The one reader of the three flags and the only caller of [onActiveChanged].
  void _reconcile( { bool refreshNow = false } ) {
    if ( !isPaneActive ) {
      // Stopping the host's machinery does not cancel an outstanding HTTP call: the
      // response would still arrive, parse and wake a backgrounded app. The mixin cancels
      // the request here; the host stops its timer, subscription or watch on the
      // `active: false` arm.
      cancelInFlight( 'pane hidden or app backgrounded' );
      onActiveChanged( active: false, refreshNow: false );
      return;
    }
    onActiveChanged( active: true, refreshNow: refreshNow );
  }

  /// Cancels and releases whatever is in the in-flight slot.
  ///
  /// A no-op when the slot is empty or already cancelled, so it is safe to call twice.
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
