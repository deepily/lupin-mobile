import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/features/task_list/presentation/task_list_pane.dart';

/// 🔴 THE SEAM BETWEEN A TAP AND THE WIRE, FOR ALL SEVEN VERBS AND FOR THE FIELD DOOR.
///
/// The companion file `task_list_tap_to_wire_test.dart` exists because a defect shipped
/// green: the verbs were rendered, the doors were built, and the callback between them
/// was a COMMENT. This file exists because of the next layer of the same thing — gap G1
/// and G2, *"built but not reachable"*: five of the seven verb payloads were written and
/// unit-tested, and no button on this pane could send any of them. `TaskListFieldChanged`
/// had a handler in the bloc since Phase 3 and NOTHING DISPATCHED IT.
///
/// ⇒ Every test here drives a REAL TAP through the REAL WIDGET TREE and asserts the
/// REQUEST THAT ACTUALLY WENT OUT. A test that asserted the button renders would have
/// passed against both defects.
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED. Five defects were reintroduced, the suite
/// re-run, and the RED COUNT BELOW IS WHAT CAME BACK — not what was predicted. The two
/// disagreed once and the table records the measurement, because a matrix written from a
/// guess is a second thing to trust and a first thing to be wrong.
///
/// | Group (7 verb cases + 12 others)      | A  | B | C | D | E |
/// |---------------------------------------|----|---|---|---|---|
/// | a verb puts ITS payload on the wire    | 🔴5| . | . | . | . |
/// | park's reason under park's OWN key     | 🔴 | . | . | . | . |
/// | fixed rides out with the receipt       | 🔴 | . | . | . | . |
/// | which verbs a row offers               | 🔴2| . | . |🔴3| . |
/// | the FIELD door (4 tests)               | .  |🔴3|🔴4| . | . |
/// | the roster (4 tests)                   | 🔴 | . |🔴2| . | . |
/// | a terminal verb arms (2 tests)         | 🔴2| . | . | . | . |
/// | the 202 and the write notice (3 tests) | 🔴3| . | . | . |🔴2|
/// |                                        | 15 | 3 | 6 | 3 | 2 |
///
///   A — `_verbsFor` reverted to the two hand-written status tests (THE SHIPPED STATE)
///   B — `onFieldChanged` dispatched `TaskListVerbPressed` instead (§4.2 backwards)
///   C — `onFieldChanged` left null — the state G2 found: handler built, nothing dispatches
///   D — `_verbsFor` re-deriving legality locally instead of calling `verbLegality`
///   E — the write notice removed, so a rolled-back write says nothing
///
/// ⚠️ EVERY COLUMN HAS A RED AND EVERY GROUP HAS ONE. Note what A reddens and what it does
/// NOT: the field door survives A untouched, because a pane offering two verbs still
/// PATCHes correctly. Two defects, two independent detectors — which is the property to
/// keep when this file is edited.
///
/// ⚠️ ONE PREDICTION WAS WRONG AND IS CORRECTED HERE. "no POST is sent for a field change"
/// was expected to stay green under C, on the reasoning that a negative passes when
/// nothing happens. It goes RED: with `onFieldChanged` null the controls are not rendered
/// at all, so the test fails looking for the dropdown, long before it could assert
/// anything about a POST. The assertion is still narrow — it catches the wrong door and
/// nothing else — but its failure under C says "the control is missing", not "a POST was
/// sent", and a reader chasing that red deserves to know which.
///
/// ⚠️ ARMING ITSELF IS THE ROW'S, guarded in `task_row_test.dart` (mutation E there). It
/// is asserted here anyway because G4 — *"arm-then-confirm protects nothing yet … no
/// terminal verb is offered, so nothing arms"* — closes on THIS pane offering one, and a
/// mechanism tested only where it is implemented is a mechanism nobody proves is
/// reachable.

/// Records what actually went on the wire and answers per request. Rachel's shape, as
/// extended in the companion file: a mounted pane polls on init AND then writes, so the
/// responder is a function of the request rather than one canned answer.
class _Recorder extends Interceptor {
  final List<RequestOptions> calls = [];
  final Response<dynamic> Function( RequestOptions ) respond;

  _Recorder( this.respond );

  /// ⚠️ A NON-2xx MUST BE REJECTED, NOT RESOLVED. `handler.resolve` SHORT-CIRCUITS Dio's
  /// `validateStatus`, so a 500 handed back through it arrives at the repository as a
  /// SUCCESS — the failure path under test would never run and the test would pass by
  /// never exercising anything. The 202 is the deliberate exception: it is a real 2xx and
  /// must travel the success path, because that is precisely what makes it dangerous.
  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    calls.add( options );
    final res    = respond( options );
    final status = res.statusCode ?? 200;
    if ( status < 200 || status >= 300 ) {
      handler.reject( DioException(
        requestOptions : options,
        response       : res,
        type           : DioExceptionType.badResponse,
      ) );
      return;
    }
    handler.resolve( res );
  }

  Iterable<RequestOptions> get writes => calls.where( ( c ) => c.method != 'GET' );
  Iterable<RequestOptions> get posts  => calls.where( ( c ) => c.method == 'POST' );
  Iterable<RequestOptions> get patches => calls.where( ( c ) => c.method == 'PATCH' );
}

Response<dynamic> _json( RequestOptions o, dynamic body, { int status = 200 } ) =>
    Response<dynamic>( requestOptions: o, statusCode: status, data: body );

Map<String, dynamic> _row( {
  required String status,
  String id           = 'row-1',
  String title        = 'a row on the board',
  String? priority    = 'P2',
  String? owner       = 'sam',
} ) =>
    <String, dynamic>{
      'id'            : id,
      'title'         : title,
      'status'        : status,
      'priority'      : priority,
      'owner_persona' : owner,
    };

Map<String, dynamic> _page( List<Map<String, dynamic>> rows ) => <String, dynamic>{
      'tasks'     : rows,
      'total'     : rows.length,
      'has_more'  : false,
      'truncated' : false,
      'warnings'  : <String>[],
    };

/// The fleet composite the roster is read from. Two live seats plus one the arbiter has
/// called offline — the offline one must never become a reassignment target.
const _fleetState = <String, dynamic>{
  'fleet_arbiter' : {
    'sessions' : [
      { 'persona' : 'tiffany', 'liveness' : { 'verdict' : 'live' } },
      { 'persona' : 'chloe',   'liveness' : { 'verdict' : 'live' } },
      { 'persona' : 'ghost',   'liveness' : { 'verdict' : 'offline' } },
    ],
  },
};

/// Mount the pane at 360×800 — ordinary Android portrait, never the 800×600 default.
Future<_Recorder> _mount(
  WidgetTester tester, {
  required List<Map<String, dynamic>> rows,
  Response<dynamic> Function( RequestOptions )? onWrite,
  bool withFleet = true,
} ) async {
  tester.view.physicalSize     = const Size( 360, 800 );
  tester.view.devicePixelRatio = 1.0;
  addTearDown( tester.view.resetPhysicalSize );
  addTearDown( tester.view.resetDevicePixelRatio );

  late final _Recorder rec;
  rec = _Recorder( ( o ) {
    if ( o.method == 'GET' ) {
      if ( o.path.contains( 'fleet-state' ) ) return _json( o, _fleetState );
      return _json( o, _page( rows ) );
    }
    return onWrite?.call( o ) ?? _json( o, const { 'status' : 'ok' } );
  } );

  final dio = Dio( BaseOptions( baseUrl: 'http://test' ) )..interceptors.add( rec );

  await tester.pumpWidget( MaterialApp(
    home : Scaffold(
      // ⚠️ A UNIQUE KEY PER MOUNT, OR A SECOND `pumpWidget` IN ONE TEST REUSES THE
      // PANE'S `State`. The row then arrives ALREADY EXPANDED and the next `_disclose`
      // COLLAPSES it — every verb vanishes and the failure reads as a missing control.
      body : BlocProvider<TaskListBloc>(
        key    : UniqueKey(),
        create : ( _ ) => TaskListBloc(
          TaskListRepository( dio ),
          TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ),
          fleet : withFleet ? FleetRepository( dio ) : null,
        ),
        child : const TaskListPane(),
      ),
    ),
  ) );
  await tester.pumpAndSettle();
  return rec;
}

Future<void> _disclose( WidgetTester tester ) async {
  await tester.tap( find.byKey( const Key( TestKeys.taskRowDisclosure ) ) );
  await tester.pumpAndSettle();
}

Future<void> _tapVerb( WidgetTester tester, String verb ) async {
  await tester.tap( find.byKey( Key( '${TestKeys.taskRowVerbPrefix}$verb' ) ) );
  await tester.pumpAndSettle();
}

/// Fill whatever the sheet is asking for and submit it.
///
/// ⚠️ A NO-OP WHEN NO SHEET OPENED, because approve and un-park ask for nothing and fire
/// on the press. Making this unconditional would have forced the per-verb loop to carry a
/// branch about which verbs are "real", which is the table's job and not the test's.
Future<void> _completeSheet(
  WidgetTester tester, {
  String reason = 'because Rick said so',
} ) async {
  if ( find.byKey( const Key( TestKeys.reasonSheet ) ).evaluate().isEmpty ) return;

  final box = find.byKey( const Key( TestKeys.reasonSheetReason ) );
  if ( box.evaluate().isNotEmpty ) {
    await tester.enterText( box, reason );
    await tester.pumpAndSettle();
  }
  final date = find.byKey( const Key( TestKeys.reasonSheetDate ) );
  if ( date.evaluate().isNotEmpty ) {
    await tester.tap( date );
    await tester.pumpAndSettle();
    await tester.tap( find.text( 'OK' ) );
    await tester.pumpAndSettle();
  }
  await tester.tap( find.byKey( const Key( TestKeys.reasonSheetSubmit ) ) );
  await tester.pumpAndSettle();
}

void main() {
  group( "the unsent mark reaches the row", _unsentMarkReachesTheRow );

  group( 'tap → wire: every verb the row offers', () {
    // 🔴 ONE CASE PER VERB, ASSERTING THE PAYLOAD THAT LEFT. Five of these seven could
    // not be pressed at all before this row: the pane offered approve and unpark, and the
    // other five payloads sat unit-tested and unreachable.
    //
    // Each entry names the status the verb is LEGAL from, because offering a verb the
    // server would refuse reads to the operator as the board being broken rather than as
    // the move being illegal.
    final cases = <String, ( String, String )>{
      // verb      : ( legal-from status, expected to_status )
      'approve'    : ( 'not_approved', 'queued' ),
      'unpark'     : ( 'parked',       'queued' ),
      'park'       : ( 'queued',       'parked' ),
      'demote'     : ( 'queued',       'not_approved' ),
      'drop'       : ( 'queued',       'dropped' ),
      'wont_fix'   : ( 'queued',       'wont_fix' ),
      'fixed'      : ( 'queued',       'done' ),
    };

    for ( final entry in cases.entries ) {
      final verb       = entry.key;
      final status     = entry.value.$1;
      final toStatus   = entry.value.$2;
      final isTerminal = verb == 'wont_fix' || verb == 'fixed';

      testWidgets( '$verb puts a POST on the wire carrying to_status $toStatus',
          ( tester ) async {
        final rec = await _mount( tester, rows: [ _row( status: status ) ] );

        await _disclose( tester );
        await _tapVerb( tester, verb );
        // A terminal verb arms first — the second press is what opens the sheet.
        if ( isTerminal ) await _tapVerb( tester, verb );
        await _completeSheet( tester );

        expect( rec.posts, isNotEmpty,
            reason: 'a tap on $verb that produces NO request is gap G1 exactly: the '
                    'payload exists, the button exists, and nothing reaches the server' );

        final sent = rec.posts.first;
        expect( sent.path, endsWith( '/transition' ),
            reason: '$verb is a STATUS change and must use the transition door' );

        final body = sent.data as Map;
        expect( body[ 'to_status' ], toStatus );
        expect( body[ 'authority' ], 'user_direct' );
        expect( body[ 'actor' ], 'rick@example.com (mobile)',
            reason: 'the provenance pair must survive the whole path' );
      } );
    }

    // 🔴 PARK FILES UNDER `park_reason`, AND THE ONLY WAY TO PROVE THE UI HONOURS THAT IS
    // FROM A TAP. The unit test proves `buildTaskVerb` does it; this proves the text the
    // operator actually typed lands in the right key.
    testWidgets( 'the reason the operator typed lands under park\'s OWN key',
        ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued' ) ] );

      await _disclose( tester );
      await _tapVerb( tester, 'park' );
      await _completeSheet( tester, reason: 'Rick ruled this not-this-quarter' );

      final body = rec.posts.first.data as Map;
      expect( body[ 'park_reason' ], 'Rick ruled this not-this-quarter' );
      expect( body.containsKey( 'reason' ), isFalse,
          reason: 'a park filed under the generic key lands with no decisive sentence' );
      expect( body[ 'next_chase_ts' ], isNotNull,
          reason: 'a park is bounded; the sheet requires the date before it will submit' );
    } );

    testWidgets( 'fixed rides out with the receipt, from a real tap', ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued' ) ] );

      await _disclose( tester );
      await _tapVerb( tester, 'fixed' );
      await _tapVerb( tester, 'fixed' );   // terminal: arms, then confirms
      await _completeSheet( tester );

      final body = rec.posts.first.data as Map;
      final receipts = body[ 'receipt_refs' ] as Map;
      expect( receipts[ 'operator_attestation' ], isNotNull,
          reason: 'the store refuses a ->done with no receipt; the multiplexer shipped '
                  'this exact bug once and every Fixed press was refused' );
      expect( receipts[ 'operator_attestation' ], contains( 'mobile' ) );
    } );
  } );

  group( 'which verbs a row offers', () {
    // ⚠️ APPROVE AND DEMOTE ARE OPPOSITE ENDS OF ONE DOOR. Offering both hands the
    // operator a move that is a no-op in one direction, which the store rejects as a
    // FAILURE rather than as nothing happening.
    testWidgets( 'a held row offers approve and not demote', ( tester ) async {
      await _mount( tester, rows: [ _row( status: 'not_approved' ) ] );
      await _disclose( tester );

      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}approve' ) ),
          findsOneWidget );
      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}demote' ) ),
          findsNothing );
    } );

    testWidgets( 'a queued row offers demote and not approve', ( tester ) async {
      await _mount( tester, rows: [ _row( status: 'queued' ) ] );
      await _disclose( tester );

      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}demote' ) ),
          findsOneWidget );
      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}approve' ) ),
          findsNothing );
    } );

    testWidgets( 'a parked row offers un-park and not park', ( tester ) async {
      await _mount( tester, rows: [ _row( status: 'parked' ) ] );
      await _disclose( tester );

      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}unpark' ) ),
          findsOneWidget );
      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}park' ) ),
          findsNothing );
    } );

    // 🔴 THE PANE DROPS TERMINAL ROWS FROM THE BOARD (Rick's 09-09 ruling), so this
    // asserts the belt as well as the braces: even if one were rendered, it would offer
    // nothing, because the server refuses every edge out of an append-only row.
    testWidgets( 'a row in every open status offers at least drop and won\'t-fix',
        ( tester ) async {
      for ( final status in [ 'queued', 'in_progress', 'parked', 'not_approved' ] ) {
        await _mount( tester, rows: [ _row( status: status ) ] );
        await _disclose( tester );

        expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}drop' ) ),
            findsOneWidget, reason: 'drop missing on a $status row' );
        expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}wont_fix' ) ),
            findsOneWidget, reason: "won't-fix missing on a $status row" );
      }
    } );
  } );

  group( 'tap → wire: the FIELD door', () {
    // 🔴 §4.2's NAMED FAILURE, ASSERTED IN BOTH DIRECTIONS. A status change sent as a
    // PATCH is silently ignored by the field door; a field change sent as a transition
    // posts to the wrong endpoint entirely. The two tests below pin each direction.
    testWidgets( 'a priority edit PATCHes, and never sends status', ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued', priority: 'P2' ) ] );
      await _disclose( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldPriority ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( 'P0' ).last );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.taskFieldPriorityUpdate ) ) );
      await tester.pumpAndSettle();

      expect( rec.patches, hasLength( 1 ),
          reason: 'G2 exactly: the handler existed and nothing dispatched to it' );

      final sent = rec.patches.first;
      expect( sent.path, isNot( endsWith( '/transition' ) ) );

      final body = sent.data as Map;
      expect( body[ 'priority' ], 'P0' );
      expect( body.containsKey( 'status' ), isFalse,
          reason: 'the field door ignores an unknown key silently — a status here is a '
                  'control that looks wired and changes nothing' );
      expect( body[ 'authority' ], 'user_direct' );
      expect( body[ 'actor' ], 'rick@example.com (mobile)' );
    } );

    testWidgets( 'no POST is sent for a field change', ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued', priority: 'P2' ) ] );
      await _disclose( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldPriority ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( 'P0' ).last );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.taskFieldPriorityUpdate ) ) );
      await tester.pumpAndSettle();

      expect( rec.posts, isEmpty,
          reason: 'priority is a FIELD; a transition POST would move the row\'s status' );
    } );

    // ⚠️ OWNER COMMITS ON CHANGE; PRIORITY DOES NOT. The asymmetry is the web's, carried
    // rather than tidied — normalising it would make this client disagree with every
    // other one about what the control does.
    testWidgets( 'an owner edit PATCHes on change, with no Update press',
        ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued', owner: 'sam' ) ] );
      await _disclose( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldOwner ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( 'chloe' ).last );
      await tester.pumpAndSettle();

      expect( rec.patches, hasLength( 1 ) );
      final body = rec.patches.first.data as Map;
      expect( body[ 'owner_persona' ], 'chloe' );
      expect( body.containsKey( 'priority' ), isFalse,
          reason: 'an omitted field must not be sent, or the PATCH clobbers a value the '
                  'operator never touched' );
      expect( body.containsKey( 'status' ), isFalse );
    } );

    // 🔴 UPDATE STAYS DISABLED UNTIL THE VALUE ACTUALLY MOVES. Rick, on the classic page:
    // "the update button would only be enabled if I had chosen a different value."
    testWidgets( 'Update is disabled until the priority actually changes',
        ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued', priority: 'P2' ) ] );
      await _disclose( tester );

      final update = find.byKey( const Key( TestKeys.taskFieldPriorityUpdate ) );
      expect( tester.widget<OutlinedButton>( update ).onPressed, isNull,
          reason: 'a live Update on an untouched row burns a round trip to assert '
                  'nothing — and on mobile data the operator paid for it' );

      await tester.tap( update );
      await tester.pumpAndSettle();
      expect( rec.writes, isEmpty );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldPriority ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( 'P0' ).last );
      await tester.pumpAndSettle();

      expect( tester.widget<OutlinedButton>( update ).onPressed, isNotNull );
    } );
  } );

  group( 'the reassignment roster comes from the LIVE fleet', () {
    // 🔴 OFFLINE PERSONAS ARE NOT TARGETS. Reassigning a row to a seat that does not
    // exist files the work with nobody: the row moves, the board looks right, and the
    // owner it now names is gone.
    testWidgets( 'a live persona is offered and an offline one is not', ( tester ) async {
      await _mount( tester, rows: [ _row( status: 'queued', owner: 'sam' ) ] );
      await _disclose( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldOwner ) ) );
      await tester.pumpAndSettle();

      expect( find.text( 'chloe' ), findsWidgets );
      expect( find.text( 'tiffany' ), findsWidgets );
      expect( find.text( 'ghost' ), findsNothing,
          reason: 'the arbiter called this session offline' );
    } );

    // ⚠️ A ROW OWNED BY SOMEONE NO LONGER LIVE MUST STILL RENDER. A Flutter dropdown
    // whose value is absent from its own items THROWS, and the case is ordinary: a row
    // owned by a persona who has since been reaped.
    testWidgets( 'a row owned by an offline persona renders without throwing',
        ( tester ) async {
      await _mount( tester, rows: [ _row( status: 'queued', owner: 'ghost' ) ] );
      await _disclose( tester );

      expect( tester.takeException(), isNull );
      expect( find.byKey( const Key( TestKeys.taskFieldOwner ) ), findsOneWidget );
    } );

    // 🔴 EVERY WAY THE FLEET CAN FAIL COLLAPSES TO AN EMPTY ROSTER, NOT AN ERROR ON THE
    // TASK BOARD. A fleet problem's text painted on a pane whose own read succeeded would
    // tell the operator their task list is broken when it is not.
    testWidgets( 'no fleet read at all still renders the pane and its verbs',
        ( tester ) async {
      final rec = await _mount(
        tester,
        rows      : [ _row( status: 'queued' ) ],
        withFleet : false,
      );
      await _disclose( tester );

      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}drop' ) ),
          findsOneWidget );
      expect( find.textContaining( 'a row on the board' ), findsWidgets );
      expect( rec.calls.where( ( c ) => c.path.contains( 'fleet-state' ) ), isEmpty );
    } );

    testWidgets( 'the roster is read ONCE on mount, not once per poll', ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued' ) ] );
      await tester.pump( const Duration( milliseconds: 200 ) );

      expect( rec.calls.where( ( c ) => c.path.contains( 'fleet-state' ) ), hasLength( 1 ),
          reason: 'the roster changes when a seat is spawned or reaped; riding the 60 s '
                  'poll would double this pane\'s requests for a list that never moves' );
    } );
  } );

  group( 'a terminal verb arms before it writes — G4 closes here', () {
    // G4: "arm-then-confirm protects nothing yet. It's built, but no terminal verb is
    // offered, so nothing arms." It is offered now, so this asserts it reaches the wire
    // only after the second press AND the sheet.
    testWidgets( 'won\'t-fix sends nothing until armed, confirmed and filled',
        ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued' ) ] );
      await _disclose( tester );

      await _tapVerb( tester, 'wont_fix' );
      expect( rec.writes, isEmpty, reason: 'the first press only arms' );

      await _tapVerb( tester, 'wont_fix' );
      expect( rec.writes, isEmpty,
          reason: 'the confirm opens the sheet; a required reason has not been given' );

      await _completeSheet( tester, reason: 'superseded by the new design' );

      expect( rec.posts, hasLength( 1 ) );
      final body = rec.posts.first.data as Map;
      expect( body[ 'to_status' ], 'wont_fix' );
      expect( body[ 'reason' ], 'superseded by the new design' );
    } );

    testWidgets( 'cancelling the sheet writes nothing and leaves the row alone',
        ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( status: 'queued' ) ] );
      await _disclose( tester );

      await _tapVerb( tester, 'drop' );
      await tester.tap( find.byKey( const Key( TestKeys.reasonSheetCancel ) ) );
      await tester.pumpAndSettle();

      expect( rec.writes, isEmpty );
      expect( find.textContaining( 'a row on the board' ), findsWidgets,
          reason: 'the optimistic drop must not survive a cancelled sheet — the row was '
                  'never written' );
    } );
  } );

  group( 'the 202 still applies to every verb', () {
    // 🔴 A 202 IS NOT AN APPROVAL. It is a 2xx, so without the branch the pane paints the
    // row as moved — "a false FACT, not a false red." The companion file proves it for
    // approve; this proves the rollback is not approve-shaped.
    testWidgets( 'a 202 on a park leaves the row on screen', ( tester ) async {
      final rec = await _mount(
        tester,
        rows    : [ _row( status: 'queued' ) ],
        onWrite : ( o ) => _json(
          o, const { 'status' : 'awaiting_human_approval', 'ticket_id' : 'tk-11' },
          status: 202,
        ),
      );

      await _disclose( tester );
      await _tapVerb( tester, 'park' );
      await _completeSheet( tester );

      expect( rec.posts, hasLength( 1 ) );
      expect( find.textContaining( 'a row on the board' ), findsWidgets,
          reason: 'a row that vanishes reads to the operator as a park that landed' );
    } );

    // 🔴 AND THE OPERATOR MUST BE TOLD. A rollback with no notice is a row that silently
    // un-happens: the park comes back, the quoted sentence they composed is gone, and
    // nothing on screen distinguishes that from a tap that missed. This pane rendered
    // `state.error` only when there were NO rows, so every write error on a populated
    // board was invisible — survivable while approve and un-park were the only reachable
    // writes, and not survivable now that five verbs each cost the operator a reason.
    testWidgets( 'a 202 tells the operator it is awaiting approval', ( tester ) async {
      await _mount(
        tester,
        rows    : [ _row( status: 'queued' ) ],
        onWrite : ( o ) => _json(
          o, const { 'status' : 'awaiting_human_approval', 'ticket_id' : 'tk-11' },
          status: 202,
        ),
      );

      await _disclose( tester );
      await _tapVerb( tester, 'park' );
      await _completeSheet( tester );

      expect( find.byKey( const Key( TestKeys.taskListWriteNotice ) ), findsOneWidget );
      expect( find.textContaining( 'awaiting approval' ), findsOneWidget,
          reason: 'a 202 is not a failure and not a success — the operator has to be '
                  'told which' );
      expect( find.textContaining( 'tk-11' ), findsOneWidget,
          reason: 'the ticket id is the only handle they have on the pending decision' );
    } );

    testWidgets( 'a failed write says so, as a live region', ( tester ) async {
      await _mount(
        tester,
        rows    : [ _row( status: 'queued' ) ],
        onWrite : ( o ) => _json( o, const { 'detail' : 'nope' }, status: 500 ),
      );

      await _disclose( tester );
      await _tapVerb( tester, 'drop' );
      await _completeSheet( tester );

      final notice = find.byKey( const Key( TestKeys.taskListWriteNotice ) );
      expect( notice, findsOneWidget );

      final handle = tester.ensureSemantics();
      expect( tester.getSemantics( notice ).hasFlag( SemanticsFlag.isLiveRegion ), isTrue,
          reason: 'the notice appears in response to a press; a TalkBack user whose '
                  'focus is still on the button is told nothing otherwise' );
      handle.dispose();

      expect( find.textContaining( 'a row on the board' ), findsWidgets,
          reason: 'the optimistic drop must be rolled back' );
    } );
  } );
}

// ═══════════════════════════════════════════════════════════════════════════════════
// THE UNSENT MARK REACHES THE ROW — the call-site audit (row 2d29006b)
// ═══════════════════════════════════════════════════════════════════════════════════
//
// 🔴 THIS TEST CLOSES A HOLE THAT WAS PROVED, NOT SUSPECTED. Deleting
// `unsentLabel: state.unsentLabelFor( … )` from `task_list_pane.dart` left the FULL
// SUITE GREEN at 1902 passing — the mark could vanish from this pane entirely and
// nothing would say so.
//
// ⚠️ AND THE SAME DEFECT HAD ALREADY HAPPENED ONCE, ON THE OTHER PANE. Row 6d25aa31's
// rebase onto a peer's rewrite of `holding_area_pane.dart` silently dropped that
// argument: no conflict, no analyzer complaint (the parameter is optional), no red test.
// It was caught by reading a staged diff. The asymmetry was the whole finding of the
// audit — the Holding Area got its guard when the loss was noticed there, and this pane
// never got one.
//
// ⇒ THE SHAPE THAT CATCHES IT IS PANE-LEVEL, NOT WIDGET-LEVEL. `task_row_test.dart`
// passes `unsentLabel` to the row by hand, so it proves the row RENDERS a mark it is
// given and can never prove a pane GIVES it one. A bloc test cannot either: it asserts
// state, and in the measured failure the state was perfectly correct while nothing on
// screen read it. Only a test that mounts the real pane, loses a real write, and looks
// at the row can tell the difference.
void _unsentMarkReachesTheRow() {
  testWidgets( 'a write the network ate puts a mark on that row', ( tester ) async {
    final rec = await _mount(
      tester,
      rows    : [ _row( status: 'queued' ) ],
      // No response at all — the one failure a restored connection could fix, and the
      // only kind that is marked.
      onWrite : ( o ) => throw DioException.connectionError(
        requestOptions : o,
        reason         : 'the signal went away',
      ),
    );

    await _disclose( tester );
    await _tapVerb( tester, 'park' );
    await _completeSheet( tester );

    expect( rec.posts, hasLength( 1 ), reason: 'the press did reach the wire' );
    expect( find.byKey( const Key( TestKeys.taskRowUnsentMark ) ), findsOneWidget,
        reason: 'the bloc records it; a state field no pane renders is not a feature' );
  } );

  testWidgets( 'and a row whose write LANDED wears no mark', ( tester ) async {
    await _mount( tester, rows: [ _row( status: 'queued' ) ] );

    await _disclose( tester );
    await _tapVerb( tester, 'park' );
    await _completeSheet( tester );

    expect( find.byKey( const Key( TestKeys.taskRowUnsentMark ) ), findsNothing,
        reason: 'a mark on every row is a mark that means nothing — and this is the '
                'half that keeps the test above honest' );
  } );
}
