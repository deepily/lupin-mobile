import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/task_list/data/new_ticket.dart';

/// The New Ticket rules, pinned to the web's `shared/task-create.js` (row b31a9ed9).
/// Every sentence asserted here is the web's, except the two the phone rewords because
/// they name something a phone does not have.
void main() {
  group( 'buildNewTicketPayload', () {
    test( 'a blank title is refused and produces no payload', () {
      final b = buildNewTicketPayload( const NewTicketFields( title: '   ' ) );
      expect( b.ok, isFalse );
      expect( b.payload, isNull );
      expect( b.error, newTicketTitleRequiredMessage );
    } );

    test( "the defaults are Rick's: P2, approved (queued), task, lupin, epic:unassigned", () {
      final p = buildNewTicketPayload( const NewTicketFields( title: ' Fix it ' ) ).payload!;
      expect( p, {
        'item_class'      : 'task',
        'title'           : 'Fix it',
        'project'         : 'lupin',
        'created_by'      : 'rick',
        'priority'        : 'P2',
        'status'          : 'queued',
        'correlation_key' : 'epic:unassigned',
      } );
    } );

    test( 'blank details and people are OMITTED, not sent as empty strings', () {
      final p = buildNewTicketPayload( const NewTicketFields( title: 't', details: ' ', ownerPersona: '' ) ).payload!;
      expect( p.containsKey( 'body' ), isFalse );
      expect( p.containsKey( 'owner_persona' ), isFalse );
      expect( p.containsKey( 'accountable_manager' ), isFalse );
    } );

    test( 'filled fields are trimmed and carried; not approved lands in the holding area', () {
      final p = buildNewTicketPayload( const NewTicketFields(
        title: 't', details: ' why ', ownerPersona: ' maria ', accountableManager: 'mr radio',
        priority: 'P0', approved: false, itemClass: 'bug', correlationKey: 'epic:x', project: 'lupin-mobile',
      ) ).payload!;
      expect( p[ 'body' ], 'why' );
      expect( p[ 'owner_persona' ], 'maria' );
      expect( p[ 'accountable_manager' ], 'mr radio' );
      expect( p[ 'priority' ], 'P0' );
      expect( p[ 'status' ], 'not_approved' );
      expect( p[ 'item_class' ], 'bug' );
      expect( p[ 'correlation_key' ], 'epic:x' );
      expect( p[ 'project' ], 'lupin-mobile' );
    } );

    test( 'a blank epic key or project falls back — the store refuses a create with no epic', () {
      final p = buildNewTicketPayload( const NewTicketFields( title: 't', correlationKey: ' ', project: '' ) ).payload!;
      expect( p[ 'correlation_key' ], 'epic:unassigned' );
      expect( p[ 'project' ], 'lupin' );
    } );

    test( 'an unknown priority or type is refused, naming the value', () {
      expect( buildNewTicketPayload( const NewTicketFields( title: 't', priority: 'P9' ) ).error,
          'Unknown priority "P9".' );
      expect( buildNewTicketPayload( const NewTicketFields( title: 't', itemClass: 'epic' ) ).error,
          'Unknown ticket type "epic".' );
    } );
  } );

  group( 'describeNewTicketResult', () {
    test( 'a queued row is created on the board, with the short id', () {
      final o = describeNewTicketResult( 201, { 'id': 'abcdef12-3456', 'status': 'queued' } );
      expect( o.state, NewTicketState.created );
      expect( o.text, 'Created abcdef12 — on the board.' );
      expect( o.row, isNotNull );
    } );

    test( 'a held row is created in the holding area', () {
      expect( describeNewTicketResult( 201, { 'id': 'abcdef12', 'status': 'not_approved' } ).text,
          'Created abcdef12 — in the holding area.' );
    } );

    test( '🔴 a 2xx with a petition is NOT created', () {
      final o = describeNewTicketResult( 201, { 'id': 'abcdef12', 'status': 'not_approved', 'petition': { 'p': 1 } } );
      expect( o.state, NewTicketState.petition );
      expect( o.text, contains( 'not on the board yet' ) );
    } );

    test( '401 / 403 / 422 carry their own wording and the server detail', () {
      expect( describeNewTicketResult( 401, null ).text, newTicketAuthRequiredMessage );
      expect( describeNewTicketResult( 403, { 'detail': 'P0 needs the operator' } ).text, 'P0 needs the operator' );
      expect( describeNewTicketResult( 403, null ).text, 'The store refused this ticket.' );
      expect( describeNewTicketResult( 422, { 'detail': [ { 'msg': 'a' }, { 'msg': 'b' } ] } ).text, 'a; b' );
      expect( describeNewTicketResult( 422, null ).text, 'The store could not accept this ticket.' );
    } );

    test( '🔴 no answer warns the row may already exist', () {
      final o = describeNewTicketResult( 0, null );
      expect( o.state, NewTicketState.unreachable );
      expect( o.text, contains( 'may already be saved' ) );
    } );

    test( 'anything else names the status and the server words', () {
      expect( describeNewTicketResult( 500, 'boom' ).text, 'The store answered 500: boom' );
      expect( describeNewTicketResult( 409, null ).text, 'The store answered 409 and gave no reason.' );
    } );
  } );

  test( 'assignee options: every non-blank name once, sorted', () {
    expect( newTicketAssigneeOptions( [
      [ 'tiffany', ' maria ', '' ],
      [ null, 'maria', 'mr radio' ],
    ] ), [ 'maria', 'mr radio', 'tiffany' ] );
  } );
}
