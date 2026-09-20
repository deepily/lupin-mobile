import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_models.dart';

/// Unit tier for the Finished Tasks derivations.
///
/// These are the functions the four columns are built from, and every one of them
/// has a recorded way of being got wrong in the web client. The tests pin the
/// behaviour, not the implementation.
void main() {
  group( "transitionTarget", () {
    test( "takes the right-hand side of a transition", () {
      expect( transitionTarget( "queued->done" ), "done" );
      expect( transitionTarget( "in_progress->wont_fix" ), "wont_fix" );
    } );

    test( "returns empty for absent or malformed input rather than throwing", () {
      // A torn row must render untinted instead of taking the pane down.
      expect( transitionTarget( null ), "" );
      expect( transitionTarget( "" ), "" );
      expect( transitionTarget( "garbage" ), "garbage" );
    } );
  } );

  group( "actorPersona", () {
    test( "a TWO-WORD persona survives — the naive leading-word split does not", () {
      // Measured wrong on 6 of 13 live rows in the web client, and those six are
      // exactly the ones this column is for.
      expect( actorPersona( "mr radio 8353ea70" ), "mr radio" );
    } );

    test( "strips a trailing session id from a one-word persona", () {
      expect( actorPersona( "krishna 420f5ec9" ), "krishna" );
    } );

    test( "a value with no trailing session id is kept WHOLE", () {
      expect( actorPersona( "Rick" ), "Rick" );
    } );

    test( "a BARE session id renders whole — visibly odd, by design", () {
      // The \s+ in the pattern is load-bearing: without a name in front of it
      // there is nothing to strip, and truncating to nothing would be worse.
      expect( actorPersona( "0e61abe3" ), "0e61abe3" );
    } );

    test( "null and blank render the em dash, not an empty cell", () {
      expect( actorPersona( null ), kFinishedUnmeasured );
      expect( actorPersona( "   " ), kFinishedUnmeasured );
    } );
  } );

  group( "relativeAge", () {
    final now = DateTime.utc( 2026, 9, 20, 12, 0 );

    test( "minutes under an hour", () {
      expect( relativeAge( now.subtract( const Duration( minutes: 7 ) ), now ), "7m" );
    } );

    test( "whole hours drop the minutes", () {
      expect( relativeAge( now.subtract( const Duration( hours: 3 ) ), now ), "3h" );
    } );

    test( "hours keep non-zero minutes", () {
      expect(
        relativeAge( now.subtract( const Duration( hours: 3, minutes: 20 ) ), now ),
        "3h20m",
      );
    } );

    test( "a day or more renders days", () {
      expect( relativeAge( now.subtract( const Duration( days: 2 ) ), now ), "2d" );
    } );

    test( "a FUTURE instant clamps to 0m rather than going negative", () {
      // Clock skew between the phone and the server is ordinary; "-3m" is not.
      expect( relativeAge( now.add( const Duration( minutes: 3 ) ), now ), "0m" );
    } );

    test( "null renders the em dash", () {
      expect( relativeAge( null, now ), kFinishedUnmeasured );
    } );
  } );

  group( "clampWindowDays / windowSinceIso", () {
    test( "clamps into the supported range", () {
      expect( clampWindowDays( 0 ), kFinishedWindowMinDays );
      expect( clampWindowDays( 99 ), kFinishedWindowMaxDays );
      expect( clampWindowDays( 7 ), 7 );
    } );

    test( "a junk value returns the default rather than throwing", () {
      expect( clampWindowDays( null ), kFinishedWindowDefaultDays );
      expect( clampWindowDays( "banana" ), kFinishedWindowDefaultDays );
      expect( clampWindowDays( double.nan ), kFinishedWindowDefaultDays );
    } );

    test( "the x24 happens exactly once — 14 days is 14 days, never 14 hours", () {
      final now   = DateTime.utc( 2026, 9, 20, 12, 0 );
      final since = DateTime.parse( windowSinceIso( 14, now ) );
      expect( now.difference( since ), const Duration( days: 14 ) );
    } );

    test( "the window clamps on the way to the wire too", () {
      final now   = DateTime.utc( 2026, 9, 20, 12, 0 );
      final since = DateTime.parse( windowSinceIso( 999, now ) );
      expect( now.difference( since ), const Duration( days: kFinishedWindowMaxDays ) );
    } );
  } );

  group( "the three terminal statuses", () {
    test( "there are THREE, and wont_fix is one of them", () {
      // Two glyphs and no won't-fix pill makes every row the Holding Area's batch
      // won't-fix produces unreachable.
      expect( kFinishedStatuses, [ "done", "dropped", "wont_fix" ] );
    } );

    test( "only done is lit by default — dropped is off too", () {
      // finishedTasksModel.ts:67. The work item's wording implied done+dropped;
      // the source is the authority and this pins which one we followed.
      expect( kFinishedDefaultShown, [ "done" ] );
    } );

    test( "every status has a face", () {
      for ( final s in kFinishedStatuses ) {
        expect( kFinishedStatusFaces[ s ], isNotNull, reason: "no face for $s" );
      }
    } );
  } );

  group( "toggleShownStatus", () {
    test( "lighting a status keeps kFinishedStatuses order", () {
      expect( toggleShownStatus( [ "done" ], "wont_fix" ), [ "done", "wont_fix" ] );
      expect( toggleShownStatus( [ "wont_fix" ], "done" ), [ "done", "wont_fix" ] );
    } );

    test( "unlighting the LAST lit status is a no-op", () {
      // An empty selection is a pane deliberately showing nothing, which reads as
      // a broken pane.
      expect( toggleShownStatus( [ "done" ], "done" ), [ "done" ] );
    } );

    test( "unlighting one of several works normally", () {
      expect( toggleShownStatus( [ "done", "dropped" ], "done" ), [ "dropped" ] );
    } );
  } );

  group( "mergeShownEvents", () {
    FinishedTaskEvent ev( int id, String status, DateTime ts ) => FinishedTaskEvent(
      id         : id,
      itemId     : "item-$id",
      ts         : ts,
      actor      : "rachel a81c72c4",
      transition : "in_progress->$status",
      reason     : "because",
      title      : "row $id",
    );

    final t0 = DateTime.utc( 2026, 9, 20, 10, 0 );
    final t1 = DateTime.utc( 2026, 9, 20, 11, 0 );

    test( "only LIT statuses contribute rows", () {
      final byStatus = {
        "done"     : [ ev( 1, "done", t0 ) ],
        "wont_fix" : [ ev( 2, "wont_fix", t1 ) ],
      };
      final rows = mergeShownEvents( byStatus, [ "done" ] );
      expect( rows.map( ( e ) => e.id ), [ 1 ] );
    } );

    test( "sorts ts DESCENDING across statuses", () {
      final byStatus = {
        "done"     : [ ev( 1, "done", t0 ) ],
        "wont_fix" : [ ev( 2, "wont_fix", t1 ) ],
      };
      final rows = mergeShownEvents( byStatus, [ "done", "wont_fix" ] );
      expect( rows.map( ( e ) => e.id ), [ 2, 1 ] );
    } );

    test( "a shared timestamp breaks on event id, so rows do not swap on repaint", () {
      final byStatus = {
        "done"    : [ ev( 5, "done", t0 ) ],
        "dropped" : [ ev( 9, "dropped", t0 ) ],
      };
      final rows = mergeShownEvents( byStatus, [ "done", "dropped" ] );
      expect( rows.map( ( e ) => e.id ), [ 9, 5 ] );
    } );

    test( "does not mutate its input", () {
      final done     = [ ev( 1, "done", t0 ) ];
      final byStatus = { "done": done };
      mergeShownEvents( byStatus, [ "done" ] );
      expect( done.length, 1 );
      expect( byStatus.keys, [ "done" ] );
    } );
  } );

  group( "FinishedTaskEvent.fromJson", () {
    test( "parses the server's wire shape", () {
      final e = FinishedTaskEvent.fromJson( {
        "id"           : 14979,
        "item_id"      : "9450c94b-9c75-4cbe-afa8-6e20d0a0d85d",
        "ts"           : "2026-09-20T00:31:08.310555+00:00",
        "actor"        : "Rachel a81c72c4",
        "transition"   : "queued->in_progress",
        "receipt_refs" : null,
        "authority"    : "standing",
        "reason"       : "picking it up",
        "title"        : "Phase 2: Finished Tasks",
      } );
      expect( e.id, 14979 );
      expect( e.title, "Phase 2: Finished Tasks" );
      expect( e.status, "in_progress" );
      expect( e.ts.toUtc().hour, 0 );
    } );

    test( "a null actor and reason survive as null", () {
      final e = FinishedTaskEvent.fromJson( {
        "id"         : 1,
        "item_id"    : "x",
        "ts"         : "2026-09-20T00:00:00+00:00",
        "actor"      : null,
        "transition" : null,
        "reason"     : null,
        "title"      : "t",
      } );
      expect( e.actor, isNull );
      expect( e.reason, isNull );
      expect( e.status, "" );
    } );
  } );
}
