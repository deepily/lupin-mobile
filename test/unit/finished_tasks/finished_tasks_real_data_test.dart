import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_models.dart';

/// The Finished Tasks model, run against REAL captured `/api/tasks/events` rows.
///
/// 🔴 WHY THIS FILE EXISTS ALONGSIDE THE HAND-WRITTEN UNIT TESTS (Tiffany,
/// 2026-09-19). A fixture written by the same hand that wrote the parser encodes
/// that hand's assumptions, so the suite can be green about a shape the server never
/// produces. These 344 rows were captured from the live endpoint by
/// `src/scripts/capture-finished-tasks-fixtures.py` over a 14-day window.
///
/// ⚠️ AND THE CAPTURE ALREADY CORRECTED ME. I had written the Why column expecting
/// `reason` to be "often null or empty". Measured: null on 3 of 344 rows and blank on
/// ZERO — the em-dash path is real but rare, and the blank-string case does not occur
/// live at all. The hand-written test that exercises it stays, because the field is
/// nullable on the wire and rare is not never; it is now labelled as the rare path
/// rather than the expected one.
void main() {
  Map<String, dynamic> loadFixture( String name ) {
    final file = File( "test/fixtures/finished_tasks/$name" );
    expect(
      file.existsSync(),
      isTrue,
      reason: "missing fixture $name — run src/scripts/capture-finished-tasks-fixtures.py",
    );
    return jsonDecode( file.readAsStringSync() ) as Map<String, dynamic>;
  }

  List<FinishedTaskEvent> rowsOf( String status ) {
    final body = loadFixture( "events_$status.json" );
    return ( body[ "events" ] as List )
        .cast<Map<String, dynamic>>()
        .map( FinishedTaskEvent.fromJson )
        .toList();
  }

  late List<FinishedTaskEvent> all;

  setUpAll( () {
    all = [
      ...rowsOf( "done" ),
      ...rowsOf( "dropped" ),
      ...rowsOf( "wont_fix" ),
    ];
  } );

  group( "every real row parses and renders", () {
    test( "all captured rows parse without throwing", () {
      expect( all, isNotEmpty );
      expect( all.length, greaterThan( 300 ) );
    } );

    test( "every row yields a renderable cell for all four columns", () {
      final now = DateTime.now();
      for ( final e in all ) {
        expect( e.title, isNotEmpty, reason: "event ${e.id} has a blank title" );
        expect( relativeAge( e.ts, now ), isNotEmpty );
        expect( actorPersona( e.actor ), isNotEmpty );
        // Why is the reason, or the em dash — never an empty cell.
        final why = ( e.reason == null || e.reason!.trim().isEmpty )
            ? kFinishedUnmeasured
            : e.reason!.trim();
        expect( why, isNotEmpty );
      }
    } );

    test( "every row's status is one this pane can render", () {
      for ( final e in all ) {
        expect(
          kFinishedStatuses.contains( e.status ),
          isTrue,
          reason: "event ${e.id} landed on '${e.status}', which has no glyph",
        );
      }
    } );

    test( "no row's age renders negative, across the whole capture", () {
      final now = DateTime.now();
      for ( final e in all ) {
        expect( relativeAge( e.ts, now ).startsWith( "-" ), isFalse );
      }
    } );
  } );

  group( "the measured shape — a change here means the server changed", () {
    late Map<String, dynamic> report;
    setUpAll( () => report = loadFixture( "nullability.json" ) );

    test( "actor is never null in live data", () {
      // 0 of 344. The em-dash path for a null actor is therefore UNEXERCISED by
      // real data — it is kept because the field is nullable on the wire, and it
      // is pinned only by the hand-written test.
      expect( ( report[ "actor" ] as Map )[ "null" ], 0 );
    } );

    test( "reason is null on a few rows and blank on none", () {
      final reason = report[ "reason" ] as Map;
      expect( reason[ "null" ], greaterThan( 0 ) );
      expect( reason[ "blank" ], 0 );
    } );

    test( "a TWO-WORD persona is not an edge case — it is nearly half the column", () {
      // 144 of 344 at capture. The naive leading-word split would be wrong on
      // every one of them, which is why actorPersona is a function and not a
      // `split(" ").first` at the use site.
      final shapes = report[ "actor_shapes" ] as Map;
      expect( shapes[ "two_word_persona" ], greaterThan( 100 ) );
    } );

    test( "some actors carry NO session id at all, and those keep every character", () {
      // 51 of 344, including values like "rick (operator foolish goat)" — a shape
      // neither the plan nor the web source's docstring anticipated. Stripping
      // anything from these would corrupt the WHO column.
      final shapes = report[ "actor_shapes" ] as Map;
      expect( shapes[ "no_session_id" ], greaterThan( 0 ) );
    } );
  } );

  group( "real actors through actorPersona", () {
    test( "a two-word persona keeps BOTH words", () {
      final twoWord = all
          .map( ( e ) => e.actor )
          .whereType<String>()
          .firstWhere(
            ( a ) => RegExp( r"^\S+\s+\S+\s+[0-9a-f]{8}$", caseSensitive: false ).hasMatch( a ),
            orElse: () => "",
          );
      expect( twoWord, isNotEmpty, reason: "no two-word persona in the capture" );
      final rendered = actorPersona( twoWord );
      expect( rendered.split( " " ).length, greaterThanOrEqualTo( 2 ) );
      expect( RegExp( r"[0-9a-f]{8}$" ).hasMatch( rendered ), isFalse );
    } );

    test( "NO rendered actor keeps a trailing session id", () {
      for ( final e in all ) {
        final rendered = actorPersona( e.actor );
        expect(
          RegExp( r"\s+[0-9a-f]{8}$", caseSensitive: false ).hasMatch( rendered ),
          isFalse,
          reason: "event ${e.id}: '${e.actor}' rendered as '$rendered'",
        );
      }
    } );

    test( "an actor with no session id survives untouched", () {
      final plain = all
          .map( ( e ) => e.actor )
          .whereType<String>()
          .where( ( a ) => !RegExp( r"\s+[0-9a-f]{8}$", caseSensitive: false ).hasMatch( a ) )
          .toList();
      expect( plain, isNotEmpty );
      for ( final a in plain ) {
        expect( actorPersona( a ), a.trim() );
      }
    } );
  } );

  group( "merging the real capture", () {
    test( "the default view shows done only, and that is most of the capture", () {
      final byStatus = <String, List<FinishedTaskEvent>>{
        for ( final s in kFinishedStatuses ) s: rowsOf( s ),
      };
      final rows = mergeShownEvents( byStatus, kFinishedDefaultShown );
      expect( rows.length, byStatus[ "done" ]!.length );
      expect( rows.every( ( e ) => e.status == "done" ), isTrue );
    } );

    test( "lighting every pill merges all three, strictly newest first", () {
      final byStatus = <String, List<FinishedTaskEvent>>{
        for ( final s in kFinishedStatuses ) s: rowsOf( s ),
      };
      final rows = mergeShownEvents( byStatus, kFinishedStatuses );
      expect( rows.length, all.length );
      for ( var i = 1; i < rows.length; i++ ) {
        final prev = rows[ i - 1 ];
        final cur  = rows[ i ];
        final ordered = prev.ts.isAfter( cur.ts ) ||
            ( prev.ts.isAtSameMomentAs( cur.ts ) && prev.id >= cur.id );
        expect( ordered, isTrue, reason: "rows $i-1/$i are out of order" );
      }
    } );
  } );
}
