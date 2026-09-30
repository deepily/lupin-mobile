import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/push/notification_tap_payload.dart';
import 'package:lupin_mobile/services/push/notification_tap_router.dart';

/// Row d9bc6f6c — the holder that carries a tap across the wait for
/// authentication.
void main() {
  late NotificationTapRouter router;

  setUp( () => router = NotificationTapRouter() );
  tearDown( () => router.dispose() );

  NotificationTapPayload tap( String id, { String? sender = "who#1" } ) =>
      NotificationTapPayload( notificationId: id, senderId: sender );

  group( "NotificationTapRouter — the pending slot", () {
    test( "a fresh router holds nothing", () {
      expect( router.hasPending, isFalse );
      expect( router.takePending(), isNull );
    } );

    test( "an offered tap is held until taken, then gone", () {
      router.offer( tap( "n-1" ) );

      expect( router.hasPending, isTrue );
      expect( router.takePending()?.notificationId, "n-1" );
      expect( router.hasPending, isFalse,
          reason: "taking consumes — a second drain must not re-route the same tap" );
      expect( router.takePending(), isNull );
    } );

    test( "the tap SURVIVES until something drains it — the whole point", () {
      // This is the cold start: the payload is offered in main(), and nothing can
      // act on it until the user has been through a fingerprint unlock. Any
      // amount of time and any number of reads may pass in between.
      router.offer( tap( "n-1" ) );

      for ( var i = 0; i < 5; i++ ) {
        expect( router.hasPending, isTrue );
      }

      expect( router.takePending()?.notificationId, "n-1" );
    } );

    test( "a second tap before the drain REPLACES the first", () {
      router.offer( tap( "n-1" ) );
      router.offer( tap( "n-2" ) );

      expect( router.takePending()?.notificationId, "n-2",
          reason: "one slot, most-recent-wins: if the user tapped twice before the "
                  "app could act, the conversation they last asked for is the one "
                  "they are waiting to see" );
      expect( router.takePending(), isNull, reason: "and the first is not queued behind it" );
    } );
  } );

  group( "NotificationTapRouter — what is refused", () {
    test( "a null payload is dropped", () {
      router.offer( null );
      expect( router.hasPending, isFalse );
    } );

    test( "an UNROUTABLE payload is dropped, and cannot displace a routable one", () {
      router.offer( tap( "n-real" ) );
      router.offer( tap( "n-fallback", sender: null ) );

      expect( router.takePending()?.notificationId, "n-real",
          reason: "a `ws_wake` fallback has no sender to select, so storing it "
                  "would spend the single slot on a tap that routes nowhere — and "
                  "in the order above it would have evicted a real one" );
    } );
  } );

  group( "NotificationTapRouter — handle-once", () {
    test( "re-offering a taken notification is a no-op", () {
      router.offer( tap( "n-1" ) );
      expect( router.takePending()?.notificationId, "n-1" );

      router.offer( tap( "n-1" ) );

      expect( router.hasPending, isFalse,
          reason: "the two delivery paths (launch details and the live callback) "
                  "may both see the same tap; deduping by id makes that harmless "
                  "instead of a second jump under the user's thumb" );
    } );

    test( "a DIFFERENT notification is still accepted after one is handled", () {
      router.offer( tap( "n-1" ) );
      router.takePending();

      router.offer( tap( "n-2" ) );

      expect( router.takePending()?.notificationId, "n-2" );
    } );

    test( "markHandled clears a slot holding the same notification", () {
      // The stream consumer's path: it routes the tap itself and reports back,
      // rather than going through takePending.
      final payload = tap( "n-1" );
      router.offer( payload );

      router.markHandled( payload );

      expect( router.hasPending, isFalse,
          reason: "otherwise the next login drain would route it a second time" );
    } );

    test( "the handled set is bounded — a long session cannot grow it forever", () {
      // 64 is the cap. Push well past it and confirm the router still works and
      // has forgotten the oldest ids (which is the correct trade: a notification
      // from 200 taps ago is not one the user is about to re-tap).
      for ( var i = 0; i < 200; i++ ) {
        router.offer( tap( "n-$i" ) );
        router.takePending();
      }

      router.offer( tap( "n-0" ) );
      expect( router.hasPending, isTrue,
          reason: "the oldest id has aged out of the dedupe window, which is the "
                  "bound working — not a leak" );

      router.takePending();
      router.offer( tap( "n-199" ) );
      expect( router.hasPending, isFalse,
          reason: "while a RECENT id is still remembered" );
    } );
  } );

  group( "NotificationTapRouter — the stream", () {
    test( "an offered tap is emitted to listeners", () async {
      final seen = <String>[];
      router.taps.listen( ( t ) => seen.add( t.notificationId ) );

      router.offer( tap( "n-1" ) );
      await Future<void>.delayed( Duration.zero );

      expect( seen, [ "n-1" ] );
    } );

    test( "a dropped tap is NOT emitted", () async {
      final seen = <String>[];
      router.taps.listen( ( t ) => seen.add( t.notificationId ) );

      router.offer( null );
      router.offer( tap( "n-fallback", sender: null ) );
      await Future<void>.delayed( Duration.zero );

      expect( seen, isEmpty );
    } );

    test( "offering after dispose does not throw", () async {
      // The app is tearing down while a tap arrives. This must not become an
      // unhandled "Cannot add new events after calling close".
      await router.dispose();

      expect( () => router.offer( tap( "n-1" ) ), returnsNormally );
    } );
  } );
}
