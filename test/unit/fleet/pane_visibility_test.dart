import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/domain/pane_visibility_mixin.dart';

/// One recorded call of the hook, so a test can assert the arguments rather than infer
/// them from a side effect.
class _Transition {
  final bool active;
  final bool refreshNow;

  /// What the mixin's in-flight slot held **at the moment the hook was called**. The
  /// inactive arm must already be empty — the mixin cancels before it delegates.
  final CancelToken? slotAtCall;

  const _Transition( this.active, this.refreshNow, this.slotAtCall );

  @override
  String toString() => 'active: $active, refreshNow: $refreshNow';
}

/// A host with the visibility half and NOTHING ELSE — no timer, no poll. This is the Live
/// Console's shape, and it is the reason the extraction exists: a WebSocket pushes to that
/// screen, so it needs every flag and none of the `Timer.periodic`.
class _VisibleOnlyBloc extends Bloc<int, int> with PaneVisibilityMixin<int, int> {
  final StreamController<AppLifecycleState> lifecycle;

  final List<_Transition> transitions = [];

  _VisibleOnlyBloc( this.lifecycle ) : super( 0 );

  @override
  Stream<AppLifecycleState> get lifecycleStream => lifecycle.stream;

  @override
  void onActiveChanged( { required bool active, required bool refreshNow } ) {
    transitions.add( _Transition( active, refreshNow, inFlightToken ) );
  }

  // Test-only reach-through: `claimRequest` / `releaseRequest` / `cancelInFlight` are
  // `@protected`, which is a lint on outside callers, not a language barrier. Exposing
  // them here keeps the tests honest about calling the real members.
  CancelToken? claim()                        => claimRequest();
  void         release( CancelToken t )       => releaseRequest( t );
  void         cancelSlot( [ String r = 'x' ] ) => cancelInFlight( r );
  CancelToken? get slot                       => inFlightToken;
}

void main() {
  late StreamController<AppLifecycleState> lifecycle;

  setUp( () => lifecycle = StreamController<AppLifecycleState>.broadcast() );
  tearDown( () => lifecycle.close() );

  _VisibleOnlyBloc host() => _VisibleOnlyBloc( lifecycle );

  group( "startVisibility subscribes, and that is ALL it does", () {
    // 🔴 THIS IS THE HALF THAT IS EASY TO GET WRONG BY BEING HELPFUL. A bloc is alive
    // before its route is on screen, so a `startVisibility()` that began work would make
    // every host work while invisible — and the obvious test, "it stops when you leave",
    // would still pass.
    test( "it fires no transition and leaves the host inactive", () async {
      final bloc = host()..startVisibility();

      expect( bloc.transitions, isEmpty,
          reason: "subscribing is not a transition — nothing is on screen yet" );
      expect( bloc.isPaneActive, isFalse );

      await bloc.close();
    } );

    test( "it is idempotent — three calls, one subscription", () async {
      final bloc = host()
        ..startVisibility()
        ..startVisibility()
        ..startVisibility();

      bloc.onPaneVisible();
      lifecycle.add( AppLifecycleState.paused );
      await Future<void>.delayed( Duration.zero );

      // A second subscription would deliver `paused` twice, and each delivery reconciles.
      expect( bloc.transitions.map( ( t ) => t.active ), [ true, false ],
          reason: "one visible, one paused. A duplicated subscription shows up as a "
                  "second `active: false`" );

      await bloc.close();
    } );

    test( "lifecycle events before startVisibility reach nothing", () async {
      final bloc = host();
      bloc.onPaneVisible();

      lifecycle.add( AppLifecycleState.paused );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.transitions, hasLength( 1 ),
          reason: "only the onPaneVisible transition — nobody is listening yet" );
      expect( bloc.isPaneActive, isTrue,
          reason: "the paused event was never received, so the app is still 'foreground'" );

      await bloc.close();
    } );
  } );

  group( "the route's two signals", () {
    test( "onPaneVisible activates with refreshNow", () async {
      final bloc = host()..startVisibility();
      bloc.onPaneVisible();

      expect( bloc.transitions.single.active, isTrue );
      expect( bloc.transitions.single.refreshNow, isTrue,
          reason: "a surface that just appeared is being looked at" );
      expect( bloc.isPaneActive, isTrue );

      await bloc.close();
    } );

    test( "onPaneHidden deactivates, and never asks for a refresh", () async {
      final bloc = host()..startVisibility();
      bloc.onPaneVisible();
      bloc.onPaneHidden();

      expect( bloc.transitions.last.active, isFalse );
      expect( bloc.transitions.last.refreshNow, isFalse,
          reason: "refreshNow with active: false is a contradiction" );
      expect( bloc.isPaneActive, isFalse );

      await bloc.close();
    } );

    test( "a repeated signal in the same direction is swallowed", () async {
      final bloc = host()..startVisibility();

      bloc.onPaneHidden();                       // never was visible
      expect( bloc.transitions, isEmpty );

      bloc.onPaneVisible();
      bloc.onPaneVisible();                      // a rebuild
      expect( bloc.transitions, hasLength( 1 ),
          reason: "the second visible is not a transition, and a host that re-fetched on "
                  "it would re-fetch on every rebuild" );

      bloc.onPaneHidden();
      bloc.onPaneHidden();
      expect( bloc.transitions, hasLength( 2 ) );

      await bloc.close();
    } );
  } );

  group( "lifecycle: five states, not one", () {
    // `resumed` is the only foreground state. Everything else goes inactive, and every
    // non-`resumed` state earns a refresh on the way back.
    for ( final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ] ) {
      test( "$state deactivates a visible surface, and the return refreshes", () async {
        final bloc = host()..startVisibility();
        bloc.onPaneVisible();

        lifecycle.add( state );
        await Future<void>.delayed( Duration.zero );
        expect( bloc.transitions.last.active, isFalse,
            reason: "$state is not a foreground state" );
        expect( bloc.isPaneActive, isFalse );

        lifecycle.add( AppLifecycleState.resumed );
        await Future<void>.delayed( Duration.zero );
        expect( bloc.transitions.last.active, isTrue );
        expect( bloc.transitions.last.refreshNow, isTrue,
            reason: "the data is as stale as the time spent away" );

        await bloc.close();
      } );
    }

    test( "resumed while already foregrounded does NOT ask for a refresh", () async {
      final bloc = host()..startVisibility();
      bloc.onPaneVisible();
      bloc.transitions.clear();

      lifecycle.add( AppLifecycleState.resumed );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.transitions.single.active, isTrue );
      expect( bloc.transitions.single.refreshNow, isFalse,
          reason: "nothing was ever left — a duplicate resumed must not cost a request" );

      await bloc.close();
    } );

    test( "a hidden surface stays inactive across a full background round trip", () async {
      final bloc = host()..startVisibility();

      lifecycle.add( AppLifecycleState.paused );
      lifecycle.add( AppLifecycleState.resumed );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.transitions.every( ( t ) => !t.active ), isTrue,
          reason: "off screen is off screen, whatever the app is doing" );
      expect( bloc.isPaneActive, isFalse );

      await bloc.close();
    } );
  } );

  group( "the single in-flight slot", () {
    // 🔴 THE GUARD USED TO LIVE IN `PanePollingMixin._fire()`, WHERE ONLY A TIMER COULD
    // REACH IT. Every wake-up now goes through `claimRequest` — a tick, a pane becoming
    // visible, a return from the background, a catch-up after a reconnect — so the
    // one-at-a-time rule is the same rule for all of them.
    test( "a second claim while one is outstanding returns null", () async {
      final bloc = host();

      final first = bloc.claim();
      expect( first, isNotNull );
      expect( bloc.claim(), isNull, reason: "one request at a time" );
      expect( bloc.slot, same( first ) );

      await bloc.close();
    } );

    test( "releasing frees the slot, and the next claim is a FRESH token", () async {
      final bloc = host();

      final first = bloc.claim()!;
      bloc.release( first );
      expect( bloc.slot, isNull );

      final second = bloc.claim();
      expect( second, isNotNull );
      expect( second, isNot( same( first ) ),
          reason: "a re-used token is a token a later cancel would already have spent" );

      await bloc.close();
    } );

    test( "a cancelled token does not block the next claim", () async {
      final bloc = host();

      final first = bloc.claim()!;
      bloc.cancelSlot( 'test' );
      expect( first.isCancelled, isTrue );

      expect( bloc.claim(), isNotNull,
          reason: "the guard asks whether a request is LIVE, not whether one ever was" );

      await bloc.close();
    } );

    test( "releasing a stale token leaves its successor alone", () async {
      final bloc = host();

      final first = bloc.claim()!;
      bloc.cancelSlot( 'hidden' );
      final second = bloc.claim()!;

      // The cancelled request's `whenComplete` lands late and releases its own token.
      bloc.release( first );

      expect( bloc.slot, same( second ),
          reason: "an identity check, not a null assignment — a late completion must not "
                  "clear the request that replaced it" );

      await bloc.close();
    } );

    test( "cancelInFlight on an empty or already-cancelled slot is a no-op", () async {
      final bloc = host();

      bloc.cancelSlot( 'nothing here' );            // empty
      expect( bloc.slot, isNull );

      final token = bloc.claim()!;
      token.cancel( 'by hand' );
      bloc.cancelSlot( 'again' );                   // must not cancel twice
      expect( token.isCancelled, isTrue );

      await bloc.close();
    } );
  } );

  group( "going inactive cancels the request BEFORE the host is told", () {
    // 🔴 CANCELLING A TIMER DOES NOT CANCEL AN OUTSTANDING HTTP REQUEST. The response
    // still arrives, still parses, still wakes a backgrounded app — with a
    // multi-hundred-KB body behind it. The ordering is what makes the host's `active:
    // false` arm simple: by the time it runs, there is nothing left to cancel.
    test( "hiding the surface cancels it, and the slot is empty at the hook", () async {
      final bloc = host()..startVisibility();
      bloc.onPaneVisible();
      final token = bloc.claim()!;

      bloc.onPaneHidden();

      expect( token.isCancelled, isTrue );
      expect( bloc.transitions.last.slotAtCall, isNull,
          reason: "the mixin cancels and clears, THEN delegates" );
      expect( bloc.slot, isNull );

      await bloc.close();
    } );

    test( "backgrounding cancels it too", () async {
      final bloc = host()..startVisibility();
      bloc.onPaneVisible();
      final token = bloc.claim()!;

      lifecycle.add( AppLifecycleState.paused );
      await Future<void>.delayed( Duration.zero );

      expect( token.isCancelled, isTrue );
      expect( bloc.transitions.last.slotAtCall, isNull );

      await bloc.close();
    } );

    test( "the ACTIVE arm hands the host a slot it can still see", () async {
      final bloc = host()..startVisibility();
      final token = bloc.claim()!;

      // A catch-up already running when the surface appears: the transition must not
      // cancel it, because nothing went away.
      bloc.onPaneVisible();

      expect( token.isCancelled, isFalse );
      expect( bloc.transitions.single.slotAtCall, same( token ) );

      await bloc.close();
    } );
  } );

  group( "close", () {
    test( "it cancels the in-flight request", () async {
      final bloc = host()..startVisibility();
      bloc.onPaneVisible();
      final token = bloc.claim()!;

      await bloc.close();

      expect( token.isCancelled, isTrue );
    } );

    test( "it cancels the lifecycle subscription", () async {
      final bloc = host()..startVisibility();
      bloc.onPaneVisible();
      await bloc.close();
      final after = bloc.transitions.length;

      lifecycle.add( AppLifecycleState.paused );
      lifecycle.add( AppLifecycleState.resumed );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.transitions, hasLength( after ),
          reason: "a live subscription would reconcile a closed bloc — and on the resumed "
                  "arm that is a fresh request from a surface nobody is looking at" );
    } );

    test( "it can be called with nothing outstanding", () async {
      final bloc = host();
      await bloc.close();
      expect( bloc.slot, isNull );
    } );
  } );

  test( "two hosts share a lifecycle stream and nothing else", () async {
    final a = host()..startVisibility();
    final b = host()..startVisibility();

    a.onPaneVisible();
    await Future<void>.delayed( Duration.zero );

    expect( a.isPaneActive, isTrue );
    expect( b.isPaneActive, isFalse );
    expect( b.transitions, isEmpty,
        reason: "a surface that is not on screen is told nothing and does nothing" );

    await a.close();
    await b.close();
  } );

  group( "the mixin order is enforced by the compiler, not by a comment", _orderTests );
}

// ═══════════════════════════════════════════════════════════════════════════════════
// MIXIN ORDER — C-6 ii, and N1's second half
// ═══════════════════════════════════════════════════════════════════════════════════

/// 🔴 A RULE THAT CANNOT FAIL IS NOT A RULE. §5 called the mixin order "load-bearing"
/// without saying what enforces it. If `PanePollingMixin` had stayed `on Bloc<E, S>`, the
/// wrong order would compile clean: `with PanePollingMixin, PaneVisibilityMixin` puts the
/// visibility teardown in the most-derived position, so `close()` would cancel the
/// request and the subscription and then hand `super.close()` a mixin whose timer is
/// still running. Nothing would fail; the timer would simply outlive the bloc.
///
/// ⇒ The `on PaneVisibilityMixin<E, S>` clause makes that a compile error. Dart cannot
/// assert "this does not compile" from inside a test, so this group asserts the clause's
/// presence in the source — the same technique, and for the same reason, as the
/// `pollInterval` census next door.
void _orderTests() {
  const pollingMixin = 'lib/features/fleet/domain/pane_polling_mixin.dart';

  const hosts = <String>[
    'lib/features/task_list/domain/task_list_bloc.dart',
    'lib/features/holding_area/domain/holding_area_bloc.dart',
    'lib/features/finished_tasks/domain/finished_tasks_bloc.dart',
    'lib/features/fleet_status/domain/fleet_status_bloc.dart',
  ];

  test( "PanePollingMixin is declared `on PaneVisibilityMixin`", () {
    final src = File( pollingMixin ).readAsStringSync();

    expect(
      src.contains( RegExp( r'mixin\s+PanePollingMixin<E,\s*S>\s+on\s+'
                           r'PaneVisibilityMixin<E,\s*S>' ) ),
      isTrue,
      reason: "$pollingMixin must declare `on PaneVisibilityMixin<E, S>`. With `on "
              "Bloc<E, S>` the wrong mixin order compiles, and a bloc's timer outlives "
              "the bloc with nothing red to show it",
    );
  } );

  for ( final path in hosts ) {
    test( "${path.split( '/' ).last} names PaneVisibilityMixin first", () {
      final src = File( path ).readAsStringSync();

      final visibilityAt = src.indexOf( 'with PaneVisibilityMixin' );
      final pollingAt    = src.indexOf( 'PanePollingMixin<' );

      expect( visibilityAt, greaterThanOrEqualTo( 0 ),
          reason: "$path does not name PaneVisibilityMixin in its `with` clause" );
      expect( pollingAt, greaterThan( visibilityAt ),
          reason: "$path lists PanePollingMixin before PaneVisibilityMixin. The polling "
                  "mixin must be the most-derived one so its close() reaches the "
                  "visibility teardown through super.close()" );
    } );
  }
}
