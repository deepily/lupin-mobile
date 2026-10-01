/// AC-S1.10 — the job-lane vocabularies carry a disposition on record, and the
/// dashboard's tab names derive from [JobLane] rather than a parallel literal.
///
/// Three lane vocabularies exist in this tree. The AC does not demand they be
/// merged; it demands the plan SAY what happens to each, and that `_queueNames`
/// be typed as `JobLane.values`. A disposition nobody asserts is a disposition
/// that silently reverts — so this file asserts both halves.
///
/// ⚠️ One check reads SOURCE TEXT and one reads the decisions record. Where the
/// subject is code, comments are stripped first: the doc comment above
/// `_queueNames` quotes the very literal it replaced, so an un-stripped scan
/// would match the explanation and pass while the literal was back.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/shared/models/job.dart';

/// Remove `///` doc comments, `//` line comments and `/* */` blocks, so a scan
/// measures CODE and never its own explanation.
String _codeOnly( String source ) {
  final noBlocks = source.replaceAll( RegExp( r'/\*.*?\*/', dotAll: true ), '' );
  return noBlocks
      .split( '\n' )
      .map( ( line ) {
        final idx = line.indexOf( '//' );
        return idx == -1 ? line : line.substring( 0, idx );
      } )
      .join( '\n' );
}

void main() {
  group( 'AC-S1.10 — lane vocabulary disposition', () {

    test( 'JobLane is the wire vocabulary: exactly the four server lane names', () {
      expect(
        JobLane.values.map( ( l ) => l.name ).toList(),
        [ 'todo', 'run', 'done', 'dead' ],
        reason: 'JobLane mirrors the server\'s STATE_TO_UI_CONTAINER; these four '
                'names are what /api/get-queue/{name} and job_state_transition use',
      );
    } );

    test( '_queueNames DERIVES from JobLane.values — no parallel string literal', () {
      const path = 'lib/features/queue/presentation/queue_dashboard_screen.dart';
      final code = _codeOnly( File( path ).readAsStringSync() );

      final decl = code
          .split( '\n' )
          .firstWhere( ( l ) => l.contains( '_queueNames' ) && l.contains( '=' ),
              orElse: () => '' );

      expect( decl, isNotEmpty, reason: '_queueNames must still be declared in $path' );
      expect( decl, contains( 'JobLane.values' ),
          reason: 'AC-S1.10: the tab names are typed as JobLane.values' );
      expect( decl.contains( '[' ), isFalse,
          reason: 'FALSIFIER: re-introducing const _queueNames = [\'todo\',\'run\',\'done\',\'dead\'] '
                  'must turn this red — the UI keeps working, which is exactly why '
                  'nothing else would catch it' );
    } );

    test( 'JobStatus disposition (kept, not superseded by JobLane) is on record in the decisions file', () {
      // The disposition lives in the decisions record, not in a doc comment, so this
      // asserts the record has a JobStatus-kept line that names the AC-S1.10 ruling.
      final record = File( 'src/docs/decisions/README.md' );
      expect( record.existsSync(), isTrue, reason: 'the decisions record must exist' );
      final line = record.readAsLinesSync().firstWhere(
          ( l ) => l.contains( ' · JobStatus-kept · ' ), orElse: () => '' );
      expect( line, isNotEmpty, reason: 'the JobStatus-kept disposition must stay on record' );
      expect( line, contains( 'AC-S1.10' ), reason: 'the record must name the ruling it carries' );
    } );

    test( 'the two enums really do disagree — 2 of 4 members differ', () {
      final status = JobStatus.values.map( ( s ) => s.name ).toSet();
      final lane   = JobLane.values.map( ( l ) => l.name ).toSet();

      expect( status.length, lane.length );
      expect( status.difference( lane ), { 'running', 'completed' } );
      expect( lane.difference( status ), { 'run', 'done' } );
      expect( status.intersection( lane ), { 'todo', 'dead' },
          reason: 'if this ever changes, the JobStatus disposition above is stale '
                  'and must be re-read before the rename lands' );
    } );
  } );
}
