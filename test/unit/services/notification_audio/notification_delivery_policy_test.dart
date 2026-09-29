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

  // ── Row f1e80e67, plan §7: mute by sender and quiet hours ────────────────
  group( "NotificationDeliveryPolicy — mute by sender", () {
    final noon = DateTime( 2026, 9, 29, 12, 0 );
    const maya = 'persona:maya';

    Future<NotificationDeliveryPolicy> muted( { bool? bypass } ) async {
      SharedPreferences.setMockInitialValues( {
        if ( bypass != null ) NotificationPreferences.keyMuteUrgentBypass: bypass,
      } );
      final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
      await prefs.muteSender( maya, '🌻 Maya' );
      return NotificationDeliveryPolicy( prefs );
    }

    test( "a muted sender is denied at every priority below urgent, on both surfaces", () async {
      final p = await muted();
      for ( final surface in NotificationSurface.values ) {
        for ( final priority in [ 'medium', 'high' ] ) {
          expect( p.allows( surface: surface, priority: priority, senderKey: maya, now: noon ), false,
                  reason: "muted Maya must be silent at ${surface.key}/$priority" );
        }
      }
    } );

    test( "an urgent from a muted sender gets through by default, and not once the bypass is off", () async {
      expect( ( await muted() ).allows(
          surface: NotificationSurface.background, priority: 'urgent', senderKey: maya, now: noon ), true );
      expect( ( await muted( bypass: false ) ).allows(
          surface: NotificationSurface.background, priority: 'urgent', senderKey: maya, now: noon ), false );
    } );

    test( "muting one sender leaves every other sender alone, and a null sender is never muted", () async {
      final p = await muted();
      expect( p.allows( surface: NotificationSurface.background, priority: 'high',
                        senderKey: 'persona:maria', now: noon ), true );
      expect( p.allows( surface: NotificationSurface.background, priority: 'high', now: noon ), true );
    } );

    test( "the bypass never resurrects an urgent the user switched off", () async {
      SharedPreferences.setMockInitialValues( {
        NotificationPreferences.priorityKey( 'background', 'urgent' ): false,
      } );
      final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
      await prefs.muteSender( maya, 'Maya' );
      expect( NotificationDeliveryPolicy( prefs ).allows(
          surface: NotificationSurface.background, priority: 'urgent', senderKey: maya, now: noon ), false );
    } );

    test( "unmuting restores the sender", () async {
      SharedPreferences.setMockInitialValues( {} );
      final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
      await prefs.muteSender( maya, 'Maya' );
      await prefs.unmuteSender( maya );
      expect( NotificationDeliveryPolicy( prefs ).allows(
          surface: NotificationSurface.background, priority: 'high', senderKey: maya, now: noon ), true );
    } );

    test( "a corrupt stored mute list mutes nobody", () async {
      final p = await policyWith( { NotificationPreferences.keyMutedSenders: '{not json' } );
      expect( p.allows( surface: NotificationSurface.background, priority: 'high',
                        senderKey: maya, now: noon ), true );
    } );
  } );

  group( "NotificationDeliveryPolicy — quiet hours", () {
    DateTime at( int h, int m ) => DateTime( 2026, 9, 29, h, m );

    Future<NotificationDeliveryPolicy> quiet( int start, int end, { bool bypass = true } ) =>
        policyWith( {
          NotificationPreferences.keyQuietEnabled      : true,
          NotificationPreferences.keyQuietStart        : start,
          NotificationPreferences.keyQuietEnd          : end,
          NotificationPreferences.keyQuietUrgentBypass : bypass,
        } );

    bool high( NotificationDeliveryPolicy p, DateTime t ) =>
        p.allows( surface: NotificationSurface.background, priority: 'high', now: t );

    test( "off by default: a fresh install is never quiet", () async {
      final p = await policyWith( {} );
      expect( high( p, at( 23, 30 ) ), true );
    } );

    test( "a window across midnight: quiet at 22:00, 23:30 and 06:59; loud at 07:00 and 21:59", () async {
      final p = await quiet( 22 * 60, 7 * 60 );
      expect( high( p, at( 22, 0 ) ), false, reason: "start is inclusive" );
      expect( high( p, at( 23, 30 ) ), false, reason: "before midnight" );
      expect( high( p, at( 0, 15 ) ), false, reason: "after midnight" );
      expect( high( p, at( 6, 59 ) ), false );
      expect( high( p, at( 7, 0 ) ), true, reason: "end is exclusive" );
      expect( high( p, at( 21, 59 ) ), true );
    } );

    test( "a same-day window: quiet 13:00-14:00 only", () async {
      final p = await quiet( 13 * 60, 14 * 60 );
      expect( high( p, at( 12, 59 ) ), true );
      expect( high( p, at( 13, 30 ) ), false );
      expect( high( p, at( 14, 0 ) ), true );
    } );

    test( "start == end is an empty window, never 24 hours of silence", () async {
      final p = await quiet( 22 * 60, 22 * 60 );
      expect( high( p, at( 22, 0 ) ), true );
      expect( high( p, at( 3, 0 ) ), true );
    } );

    test( "urgent gets through quiet hours by default, and not once the bypass is off", () async {
      final t = at( 23, 30 );
      expect( ( await quiet( 22 * 60, 7 * 60 ) ).allows(
          surface: NotificationSurface.background, priority: 'urgent', now: t ), true );
      expect( ( await quiet( 22 * 60, 7 * 60, bypass: false ) ).allows(
          surface: NotificationSurface.background, priority: 'urgent', now: t ), false );
    } );

    test( "with no urgent bypass, quiet hours deny every priority", () async {
      // This is what lets the background pre-flight (anyAllowedOn, which asks
      // with the real clock) skip the fetch entirely during quiet hours.
      final p = await quiet( 0, 23 * 60 + 59, bypass: false );
      for ( final priority in NotificationPreferences.priorities ) {
        expect( p.allows( surface: NotificationSurface.background, priority: priority,
                          now: at( 12, 0 ) ), false );
      }
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
