import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/push/unplayed_queue_order.dart';

/// Tiffany's ruling, 2026-09-28: sort the list endpoint's items ascending by
/// timestamp, and prove it with a list handed over in DESCENDING order.
void main() {
  Map<String, dynamic> item( String id, String? timestamp ) => {
    'id'        : id,
    'message'   : 'body of $id',
    'priority'  : 'medium',
    if ( timestamp != null ) 'timestamp': timestamp,
  };

  List<String> idsOf( List<Map<String, dynamic>> items ) =>
      [ for ( final i in items ) i[ 'id' ] as String ];

  test( "a DESCENDING list comes back oldest first (Tiffany's named case)", () {
    final newestFirst = [
      item( 'c', '2026-09-28T10:00:00-04:00' ),
      item( 'b', '2026-09-28T09:00:00-04:00' ),
      item( 'a', '2026-09-28T08:00:00-04:00' ),
    ];
    expect( idsOf( oldestFirst( newestFirst ) ), [ 'a', 'b', 'c' ] );
  } );

  test( "an already-ascending list is left in that order", () {
    final ascending = [
      item( 'a', '2026-09-28T08:00:00-04:00' ),
      item( 'b', '2026-09-28T09:00:00-04:00' ),
      item( 'c', '2026-09-28T10:00:00-04:00' ),
    ];
    expect( idsOf( oldestFirst( ascending ) ), [ 'a', 'b', 'c' ] );
  } );

  test( "instants are compared across UTC OFFSETS, where a string sort gets it backwards", () {
    // 01:00-04:00 is 05:00Z; 02:00+00:00 is 02:00Z. So the SECOND one is older,
    // even though '01:00-04:00' sorts before '02:00+00:00' as text. This is the
    // shape a timezone-config change or a DST boundary actually produces.
    final mixed = [
      item( 'later',   '2026-09-28T01:00:00-04:00' ),
      item( 'earlier', '2026-09-28T02:00:00+00:00' ),
    ];
    expect( idsOf( oldestFirst( mixed ) ), [ 'earlier', 'later' ],
            reason: "a lexicographic compare would answer ['later','earlier']" );
  } );

  test( "an item with no timestamp, or an unparseable one, is treated as oldest rather than starved", () {
    final withGaps = [
      item( 'dated',        '2026-09-28T09:00:00-04:00' ),
      item( 'missing',      null ),
      item( 'unparseable',  'yesterday afternoon' ),
    ];
    expect( idsOf( oldestFirst( withGaps ) ), [ 'missing', 'unparseable', 'dated' ] );
  } );

  test( "ties keep their original relative order, so the sort cannot flake", () {
    const sameInstant = '2026-09-28T09:00:00-04:00';
    final tied = [
      item( 'first',  sameInstant ),
      item( 'second', sameInstant ),
      item( 'third',  sameInstant ),
    ];
    // Run it repeatedly: an unstable sort would eventually disagree with itself.
    for ( var i = 0; i < 20; i++ ) {
      expect( idsOf( oldestFirst( tied ) ), [ 'first', 'second', 'third' ] );
    }
  } );

  test( "the caller's list is not mutated", () {
    final original = [
      item( 'c', '2026-09-28T10:00:00-04:00' ),
      item( 'a', '2026-09-28T08:00:00-04:00' ),
    ];
    oldestFirst( original );
    expect( idsOf( original ), [ 'c', 'a' ] );
  } );

  test( "an empty list is an empty list", () {
    expect( oldestFirst( [] ), isEmpty );
  } );
}
