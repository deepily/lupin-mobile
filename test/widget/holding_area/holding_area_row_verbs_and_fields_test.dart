import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/features/holding_area/presentation/holding_area_pane.dart';

/// Gaps G5 and G2 on the Holding Area: per-row verbs through the shared sheet, and the
/// priority / owner controls through the FIELD door.
///
/// 🔴 THIS PANE DECLINED FIVE OF THE SEVEN VERBS ON PURPOSE, AND THE REASON IT GAVE WAS
/// CORRECT. `_heldRowVerbs()` returned `[ approve ]` under a comment naming the trap:
/// four verbs carry a REQUIRED reason, the row had no surface to collect one, and
/// `TaskVerb.wontFix( reason: '' )` is *"a button whose every press is a guaranteed
/// 422."* Shipping the verb would have looked like the precise instrument the batch
/// control's own hint points the operator at, while being a control that cannot work.
///
/// ⇒ The shared sheet is that surface. What this file proves is not that the sheet
/// exists — Sam's row owns that — but that THIS pane reaches it, and that what leaves
/// goes through the right door. A verb tested only on the Task List is a verb nobody has
/// shown is reachable from here.
///
/// ⚠️ EVERY CASE UNFOLDS A GROUP FIRST. Rick's N2 ruling folds the personas by default,
/// so a held row is not in the widget tree until its persona is opened. A test that
/// forgot would fail looking for the disclosure control, which reads as "the row is
/// missing" rather than "the group is shut".

/// Records what actually went on the wire. Sam's shape, carried: a mounted pane polls on
/// init AND then writes, so the responder is a function of the request.
class _Recorder extends Interceptor {
  final List<RequestOptions> calls = [];
  final Response<dynamic> Function( RequestOptions ) respond;

  _Recorder( this.respond );

  /// ⚠️ A NON-2xx MUST BE REJECTED, NOT RESOLVED. `handler.resolve` short-circuits Dio's
  /// `validateStatus`, so a 500 handed back through it arrives at the repository as a
  /// SUCCESS and the failure path under test never runs.
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

  Iterable<RequestOptions> get posts   => calls.where( ( c ) => c.method == 'POST' );
  Iterable<RequestOptions> get patches => calls.where( ( c ) => c.method == 'PATCH' );
}

Response<dynamic> _json( RequestOptions o, dynamic body, { int status = 200 } ) =>
    Response<dynamic>( requestOptions: o, statusCode: status, data: body );

Map<String, dynamic> _row( {
  String id       = 'held-1',
  String status   = 'not_approved',
  String? priority = 'P2',
  String? owner    = 'sam',
  String filer     = 'mr radio 8fa24215',
} ) =>
    <String, dynamic>{
      'id'            : id,
      'title'         : '[LUPIN-MOBILE] a held row with a long fleet-style title',
      'status'        : status,
      'priority'      : priority,
      'owner_persona' : owner,
      'created_by'    : filer,
    };

Map<String, dynamic> _page( List<Map<String, dynamic>> rows ) => <String, dynamic>{
      'tasks'     : rows,
      'total'     : rows.length,
      'has_more'  : false,
      'truncated' : false,
      'warnings'  : <String>[],
    };

/// Two live seats plus one the arbiter has called offline — the offline one must never
/// become a reassignment target.
const _fleetState = <String, dynamic>{
  'fleet_arbiter' : {
    'sessions' : [
      { 'persona' : 'tiffany', 'liveness' : { 'verdict' : 'live' } },
      { 'persona' : 'chloe',   'liveness' : { 'verdict' : 'live' } },
      { 'persona' : 'ghost',   'liveness' : { 'verdict' : 'offline' } },
    ],
  },
};

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
      body : BlocProvider<HoldingAreaBloc>(
        // ⚠️ A UNIQUE KEY PER MOUNT, or a second `pumpWidget` in one test reuses the
        // pane's `State` and the group arrives already unfolded.
        key    : UniqueKey(),
        create : ( _ ) => HoldingAreaBloc(
          HoldingAreaRepository( dio ),
          TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ),
          fleet : withFleet ? FleetRepository( dio ) : null,
        ),
        child : const HoldingAreaPane(),
      ),
    ),
  ) );
  await tester.pumpAndSettle();
  return rec;
}

/// Open the persona group, then the row. Two disclosures, and both are load-bearing.
Future<void> _openRow( WidgetTester tester, { String filer = 'Mr Radio' } ) async {
  await tester.tap( find.byKey( Key( '${TestKeys.holdingGroupTogglePrefix}$filer' ) ) );
  await tester.pumpAndSettle();
  await tester.tap( find.byKey( const Key( TestKeys.taskRowDisclosure ) ).first );
  await tester.pumpAndSettle();
}

Future<void> _tapVerb( WidgetTester tester, String verb ) async {
  await tester.tap( find.byKey( Key( '${TestKeys.taskRowVerbPrefix}$verb' ) ) );
  await tester.pumpAndSettle();
}

/// Fill whatever the sheet asks for and submit. A no-op when no sheet opened, because
/// approve asks for nothing and fires on the press.
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
  group( '🔴 G5 — the verbs a HELD row offers, from a real tap', () {
    // Every row on this pane is `not_approved`, so `verbLegality` decides the set and
    // this pane does not get a second opinion. These are that function's answer,
    // asserted HERE because a verb proven legal in a unit test is not a verb anyone has
    // shown is pressable from this pane.
    for ( final verb in <String>[ 'approve', 'drop', 'wont_fix', 'fixed' ] ) {
      testWidgets( 'a held row offers $verb', ( tester ) async {
        await _mount( tester, rows: [ _row() ] );
        await _openRow( tester );

        expect( find.byKey( Key( '${TestKeys.taskRowVerbPrefix}$verb' ) ), findsOneWidget );
      } );
    }

    testWidgets( '🔴 it does NOT offer demote — approve is the other end of that door',
        ( tester ) async {
      // Offering both hands the operator a move that is a no-op in one direction, which
      // the store rejects as a FAILURE rather than as nothing happening.
      await _mount( tester, rows: [ _row() ] );
      await _openRow( tester );

      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}demote' ) ), findsNothing );
    } );

    testWidgets( 'it does NOT offer park or unpark on a held row', ( tester ) async {
      await _mount( tester, rows: [ _row() ] );
      await _openRow( tester );

      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}park' ) ), findsNothing );
      expect( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}unpark' ) ), findsNothing );
    } );

    testWidgets( "🔴 won't-fix now REACHES the server with the operator's reason",
        ( tester ) async {
      // 🔴 THE EXACT CONTROL THIS PANE REFUSED TO SHIP. Its batch hint tells the operator
      // *"use the per-row control when the reasons differ"* — and until now there was no
      // per-row control to use. A hint pointing at a button that does not exist is worse
      // than the missing button.
      final rec = await _mount( tester, rows: [ _row() ] );
      await _openRow( tester );

      await _tapVerb( tester, 'wont_fix' );
      await _tapVerb( tester, 'wont_fix' );   // terminal: arms, then opens the sheet
      await _completeSheet( tester, reason: 'superseded by the rewrite' );

      expect( rec.posts, isNotEmpty,
          reason: 'a tap that produces NO request is gap G5 exactly' );

      final sent = rec.posts.first;
      expect( sent.path, endsWith( '/transition' ) );

      final body = sent.data as Map;
      expect( body[ 'to_status' ], 'wont_fix' );
      expect( body[ 'reason' ], 'superseded by the rewrite',
          reason: 'an EMPTY reason here is the guaranteed 422 this pane refused to ship' );
      expect( body[ 'actor' ], 'rick@example.com (mobile)' );
    } );

    testWidgets( 'approve still fires on one press, asking for nothing', ( tester ) async {
      final rec = await _mount( tester, rows: [ _row() ] );
      await _openRow( tester );

      await _tapVerb( tester, 'approve' );

      final body = rec.posts.first.data as Map;
      expect( body[ 'to_status' ], 'queued' );
    } );

    testWidgets( 'fixed rides out with its receipt', ( tester ) async {
      final rec = await _mount( tester, rows: [ _row() ] );
      await _openRow( tester );

      await _tapVerb( tester, 'fixed' );
      await _tapVerb( tester, 'fixed' );
      await _completeSheet( tester );

      final receipts = ( rec.posts.first.data as Map )[ 'receipt_refs' ] as Map;
      expect( receipts[ 'operator_attestation' ], contains( 'mobile' ),
          reason: 'the store refuses a ->done with no receipt' );
    } );
  } );

  group( '🔴 G2 — priority and owner, through the FIELD door', () {
    testWidgets( 'the controls are on the held row at all', ( tester ) async {
      // They render because `onFieldChanged` is non-null — the pane offering somewhere
      // for their output to go IS the mechanism, not a pane discriminator.
      await _mount( tester, rows: [ _row() ] );
      await _openRow( tester );

      expect( find.byKey( const Key( TestKeys.taskFieldPriority ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.taskFieldOwner ) ), findsOneWidget );
    } );

    testWidgets( '🔴 a priority change PATCHes, and carries no status', ( tester ) async {
      // §4.2's named failure, read backwards: a field change posted to the transition
      // endpoint. The door is the assertion.
      final rec = await _mount( tester, rows: [ _row( priority: 'P2' ) ] );
      await _openRow( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldPriority ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( 'P0' ).last );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.taskFieldPriorityUpdate ) ) );
      await tester.pumpAndSettle();

      expect( rec.patches, isNotEmpty,
          reason: 'gap G2: the write path existed and nothing could reach it' );
      expect( rec.posts, isEmpty,
          reason: 'a field change on the TRANSITION door is §4.2 backwards' );

      final body = rec.patches.first.data as Map;
      expect( body[ 'priority' ], 'P0' );
      expect( body.containsKey( 'status' ), isFalse,
          reason: 'the field door cannot carry a status — that is what makes it a '
                  'separate door' );
    } );

    testWidgets( 'an owner change PATCHes owner_persona and nothing else', ( tester ) async {
      final rec = await _mount( tester, rows: [ _row( owner: 'sam' ) ] );
      await _openRow( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldOwner ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( 'chloe' ).last );
      await tester.pumpAndSettle();

      expect( rec.patches, isNotEmpty );
      final body = rec.patches.first.data as Map;
      expect( body[ 'owner_persona' ], 'chloe' );
      expect( body.containsKey( 'priority' ), isFalse,
          reason: 'an omitted field must not be sent, or it clobbers what it did not name' );
    } );

    testWidgets( '🔴 an OFFLINE persona is not a reassignment target', ( tester ) async {
      await _mount( tester, rows: [ _row() ] );
      await _openRow( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskFieldOwner ) ) );
      await tester.pumpAndSettle();

      expect( find.text( 'tiffany' ), findsWidgets );
      expect( find.text( 'ghost' ), findsNothing,
          reason: 'handing work to a seat the arbiter has called offline is a write '
                  'nobody will read' );
    } );

    testWidgets( 'with the arbiter unreachable the pane still renders its held work',
        ( tester ) async {
      // The roster read is a COURTESY on a pane about held rows. Its failure degrades the
      // owner control; it must not paint an error over the held set.
      await _mount( tester, rows: [ _row() ], withFleet: false );
      await _openRow( tester );

      expect( find.byKey( const Key( TestKeys.holdingErrorView ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.taskFieldPriority ) ), findsOneWidget );
    } );
  } );
}
