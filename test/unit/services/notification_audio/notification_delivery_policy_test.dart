import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_delivery_policy.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

/// Row 7cac3a17. The full truth table for "should this be raised at all?":
/// 2 surfaces x 4 priorities, times the master switch and each surface switch.
void main() {
  const all = NotificationPreferences.priorities;

  Future<NotificationPreferences> prefsWith( Map<String, Object> seed ) async {
    SharedPreferences.setMockInitialValues( seed );
    return NotificationPreferences( await SharedPreferences.getInstance() );
  }

  Future<NotificationDeliveryPolicy> policyWith( Map<String, Object> seed ) async =>
      NotificationDeliveryPolicy( await prefsWith( seed ) );

  group( "NotificationDeliveryPolicy — defaults reproduce today's behaviour", () {
    test( "a fresh install allows every priority in the background", () async {
      final p = await policyWith( {} );
      for ( final priority in all ) {
        expect( p.allows( surface: NotificationSurface.background, priority: priority ), true,
                reason: "background/$priority should default ON — the wake path "
                        "shows every item it fetches today" );
      }
    } );

    test( "a fresh install allows medium, high and urgent in the foreground but NOT low", () async {
      final p = await policyWith( {} );
      expect( p.allows( surface: NotificationSurface.foreground, priority: 'low' ), false,
              reason: "low is already silent in the foreground today; defaulting it ON "
                      "would start raising notifications that never were raised" );
      for ( final priority in [ 'medium', 'high', 'urgent' ] ) {
        expect( p.allows( surface: NotificationSurface.foreground, priority: priority ), true );
      }
    } );
  } );

  group( "NotificationDeliveryPolicy — the three gates", () {
    test( "the master switch denies every surface at every priority", () async {
      final p = await policyWith( { NotificationPreferences.keyEnabled: false } );
      for ( final surface in NotificationSurface.values ) {
        for ( final priority in all ) {
          expect( p.allows( surface: surface, priority: priority ), false,
                  reason: "master OFF must deny ${surface.key}/$priority" );
        }
        expect( p.anyAllowedOn( surface ), false );
      }
    } );

    test( "a surface switch denies only its own surface", () async {
      final p = await policyWith( { NotificationPreferences.keyBackgroundEnabled: false } );
      for ( final priority in all ) {
        expect( p.allows( surface: NotificationSurface.background, priority: priority ), false );
      }
      expect( p.allows( surface: NotificationSurface.foreground, priority: 'high' ), true,
              reason: "turning the background off must not touch the foreground" );
      expect( p.anyAllowedOn( NotificationSurface.background ), false );
      expect( p.anyAllowedOn( NotificationSurface.foreground ), true );
    } );

    test( "a priority checkbox denies only that priority on that surface", () async {
      final p = await policyWith( {
        NotificationPreferences.priorityKey( 'background', 'low' ): false,
      } );
      expect( p.allows( surface: NotificationSurface.background, priority: 'low' ), false );
      for ( final priority in [ 'medium', 'high', 'urgent' ] ) {
        expect( p.allows( surface: NotificationSurface.background, priority: priority ), true );
      }
      // The same priority on the OTHER surface is a separate checkbox.
      expect( p.allows( surface: NotificationSurface.foreground, priority: 'medium' ), true );
    } );

    test( "every combination of the three gates agrees with master AND surface AND priority", () async {
      for ( final master in [ true, false ] ) {
        for ( final surfaceOn in [ true, false ] ) {
          for ( final priorityOn in [ true, false ] ) {
            for ( final surface in NotificationSurface.values ) {
              for ( final priority in all ) {
                final p = await policyWith( {
                  NotificationPreferences.keyEnabled                      : master,
                  NotificationPreferences.keyBackgroundEnabled            : surfaceOn,
                  NotificationPreferences.keyForegroundEnabled            : surfaceOn,
                  NotificationPreferences.priorityKey( surface.key, priority ) : priorityOn,
                } );
                expect(
                  p.allows( surface: surface, priority: priority ),
                  master && surfaceOn && priorityOn,
                  reason: "master=$master surface=$surfaceOn priority=$priorityOn "
                          "on ${surface.key}/$priority",
                );
              }
            }
          }
        }
      }
    } );
  } );

  group( "NotificationDeliveryPolicy — anyAllowedOn, the background pre-flight", () {
    test( "false only when every single priority is denied", () async {
      final p = await policyWith( {
        for ( final priority in all )
          NotificationPreferences.priorityKey( 'background', priority ): false,
      } );
      expect( p.anyAllowedOn( NotificationSurface.background ), false );
    } );

    test( "true when even one priority survives — this is what keeps urgent alive", () async {
      final p = await policyWith( {
        for ( final priority in [ 'low', 'medium', 'high' ] )
          NotificationPreferences.priorityKey( 'background', priority ): false,
      } );
      expect( p.anyAllowedOn( NotificationSurface.background ), true );
      expect( p.allows( surface: NotificationSurface.background, priority: 'urgent' ), true );
    } );
  } );

  test( "an unrecognised priority is DENIED, not guessed at", () async {
    final p = await policyWith( {} );
    // A new server tier is something the user has never been shown a checkbox
    // for, so there is no consent to infer. Silently treating it as 'medium'
    // would raise notifications nobody agreed to.
    expect( p.allows( surface: NotificationSurface.background, priority: 'catastrophic' ), false );
    expect( p.allows( surface: NotificationSurface.foreground, priority: '' ), false );
  } );
}
