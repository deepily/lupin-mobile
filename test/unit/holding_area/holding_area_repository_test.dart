import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';

import '../_helpers/stub_dio.dart';

/// The Holding Area's READ door.
///
/// 🔴 THE QUERY IS ASSERTED PARAMETER BY PARAMETER, NOT AS ONE STRING. Each of these
/// four is load-bearing for a different reason, and a whole-string comparison fails
/// uninformatively the moment anyone reorders them — which teaches the next hand to
/// update the expected string rather than to ask which parameter changed.

Map<String, dynamic> _fixture( String name ) =>
    jsonDecode( File( 'test/fixtures/tasks/$name' ).readAsStringSync() )
        as Map<String, dynamic>;

void main() {
  late StubAdapter adapter;
  late HoldingAreaRepository repo;

  setUp( () {
    adapter = StubAdapter();
    repo    = HoldingAreaRepository( makeDio( adapter ) );
  } );

  group( "the query", () {
    test( "pins status=not_approved — the held set IS the pane", () {
      // 🔴 THE STORE EXCLUDES HELD ROWS BY DEFAULT, INCLUDING FROM THE UN-STATUS'D
      // CATCH-ALL. A pane that inherited the default query would render empty against a
      // board full of held work and look like it was working.
      expect( HoldingAreaRepository.path, contains( 'status=not_approved' ) );
    } );

    test( "keeps char_budget=0 AND adds terse=true", () {
      // The measured pairing. Dropping `char_budget=0` does not trim rows gently — it
      // applies the default 100,000-char budget against ~4,242-char rows and admits
      // about 23 of 500. `terse=true` is the lever: smaller rows, not fewer rows.
      expect( HoldingAreaRepository.path, contains( 'char_budget=0' ) );
      expect( HoldingAreaRepository.path, contains( 'terse=true' ) );
    } );

    test( "does NOT send hide_parked — the status is already pinned", () {
      // Meaningful only across statuses. A parked row is by definition not held, so the
      // parameter here would be a claim about this query that is not true of it.
      expect( HoldingAreaRepository.path, isNot( contains( 'hide_parked' ) ) );
    } );

    test( "the path the repository actually GETs is the path it declares", () async {
      // The constant and the request drifting apart is exactly the defect these
      // assertions would otherwise miss, because every one of them reads the constant.
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area.json' ) );

      await repo.fetch();

      expect( adapter.captured.single.path, HoldingAreaRepository.path );
      expect( adapter.captured.single.method, 'GET' );
    } );
  } );

  group( "the envelope", () {
    test( "parses the captured page into rows", () async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area.json' ) );

      final page = await repo.fetch();

      expect( page.rows.length, 8 );
      expect( page.rows.every( ( r ) => r.status == 'not_approved' ), isTrue );
    } );

    test( "🔴 has_more makes the page INCOMPLETE, so the banner can fire", () async {
      // The captured fixture carries `has_more: true`. Reading `tasks` and discarding
      // the envelope is the silent-truncation failure: held rows off the end of the
      // page are held work the operator cannot see, in the pane whose job is showing it.
      final page = await ( () {
        adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
            ( _ ) => jsonBody( _fixture( 'holding_area.json' ) );
        return repo.fetch();
      } )();

      expect( page.hasMore, isTrue );
      expect( page.isIncomplete, isTrue );
    } );

    test( "truncated alone is enough to be incomplete", () async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] = ( _ ) => jsonBody( {
            'tasks'     : <dynamic>[],
            'truncated' : true,
            'has_more'  : false,
            'total'     : 9,
          } );

      final page = await repo.fetch();

      expect( page.isIncomplete, isTrue, reason: 'the byte budget cut it, not the row cap' );
      expect( page.total, 9 );
    } );

    test( "an empty page is empty, not an error", () async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area_empty.json' ) );

      final page = await repo.fetch();

      expect( page.rows, isEmpty );
      expect( page.isIncomplete, isFalse );
    } );

    test( "a TERSE row still parses — the query shape this pane actually uses", () async {
      // ⚠️ THE CAPTURED FIXTURE WAS TAKEN WITHOUT `terse=true`, SO IT IS A FULL PAGE AND
      // A SUPERSET OF WHAT THIS REPOSITORY WILL RECEIVE. Parsing it proves nothing about
      // the terse shape, where `body` and `item_class` are both absent. A pane that
      // throws on the query shape it is specified to use is a pane that never ran.
      final full  = _fixture( 'holding_area.json' );
      final terse = {
        ...full,
        'tasks' : ( full[ 'tasks' ] as List )
            .cast<Map<String, dynamic>>()
            .map( ( r ) => { ...r }..removeWhere( ( k, _ ) => k == 'body' || k == 'item_class' ) )
            .toList(),
      };
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] = ( _ ) => jsonBody( terse );

      final page = await repo.fetch();

      expect( page.rows.length, 8 );
      expect( page.rows.first.detail, isNull );
      expect( page.rows.first.itemClass, isNull );
      expect( page.rows.first.id, isNotEmpty, reason: 'the cells that DO survive terse' );
    } );
  } );

  group( "failure", () {
    test( "🔴 a cancellation passes through UNTRANSLATED", () async {
      // A poll cancelled because the pane went away is the lifecycle rule working.
      // Wrapping it in the fetch exception would take the bloc's only means of telling
      // "the user left" apart from "the server is down".
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] = ( _ ) =>
          throw DioException.requestCancelled(
            requestOptions : RequestOptions( path: HoldingAreaRepository.path ),
            reason         : 'pane hidden',
          );

      await expectLater(
        repo.fetch(),
        throwsA( isA<DioException>()
            .having( ( e ) => e.type, 'type', DioExceptionType.cancel ) ),
      );
    } );

    test( "a real transport failure becomes HoldingAreaFetchException", () async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] = ( _ ) =>
          throw DioException.connectionError(
            requestOptions : RequestOptions( path: HoldingAreaRepository.path ),
            reason         : 'refused',
          );

      await expectLater( repo.fetch(), throwsA( isA<HoldingAreaFetchException>() ) );
    } );
  } );
}
