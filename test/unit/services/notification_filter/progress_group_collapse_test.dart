import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/notification_filter/progress_group_collapse.dart';

void main() {
  group( 'collapseByProgressGroup', () {
    // (id, groupKey)
    String? keyOf( ( String, String? ) r ) => r.$2;

    test( 'consecutive same-key items collapse; null keys stay single; a re-appearing key starts a NEW group (order preserved)', () {
      final items = <( String, String? )>[
        ( 'a', 'pg-1' ), ( 'b', 'pg-1' ), ( 'c', 'pg-1' ),
        ( 'd', null ),
        ( 'e', 'pg-2' ),
        ( 'f', 'pg-1' ), ( 'g', 'pg-1' ),
        ( 'h', null ),
      ];
      final g = collapseByProgressGroup( items, keyOf );
      expect( g.map( ( x ) => x.items.map( ( i ) => i.$1 ).join() ).toList(), [ 'abc', 'd', 'e', 'fg', 'h' ] );
      expect( g[ 0 ].isCollapsed, isTrue );
      expect( g[ 0 ].count, 3 );
      expect( g[ 0 ].latest.$1, 'c' );
      expect( g[ 1 ].isCollapsed, isFalse );
      expect( g[ 2 ].isCollapsed, isFalse, reason: 'a lone keyed item is not a collapse' );
      expect( g[ 3 ].key, 'pg-1' );
    } );

    test( 'enabled=false ⇒ every item is its own group', () {
      final items = <( String, String? )>[ ( 'a', 'pg-1' ), ( 'b', 'pg-1' ) ];
      final g = collapseByProgressGroup( items, keyOf, enabled: false );
      expect( g.length, 2 );
      expect( g.every( ( x ) => !x.isCollapsed ), isTrue );
    } );

    test( 'empty input ⇒ empty output; never mutates the input list', () {
      expect( collapseByProgressGroup<( String, String? )>( const [], keyOf ), isEmpty );
      final items = <( String, String? )>[ ( 'a', 'x' ), ( 'b', 'x' ) ];
      final g = collapseByProgressGroup( items, keyOf );
      g.first.items.add( ( 'z', 'x' ) );
      expect( items.length, 2 );
    } );
  } );
}
