import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/build_info.dart';
import 'package:lupin_mobile/core/build_info_footer.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';

/// The drawer footer at phone width: the branch line may be cut, the detail line never is.
void main() {
  Future<void> pump( WidgetTester tester, BuildInfo info, double width ) async {
    await tester.pumpWidget( MaterialApp(
      home : Scaffold(
        body : Align(
          alignment : Alignment.bottomLeft,
          child     : SizedBox( width: width, child: BuildInfoFooter( info: info ) ),
        ),
      ),
    ) );
  }

  const stamped = BuildInfo(
    time: '2026-10-10T13:12:00-04:00', zone: 'EDT', sha: '4c26045', dirty: true,
    branch: 'wip-v0.2.2-2026.09.30-tracking-lupin', number: 3, push: true,
  );

  testWidgets( 'a stamped build shows the branch line and the detail line', ( tester ) async {
    await pump( tester, stamped, 320 );
    expect( tester.widget<Text>( find.byKey( const Key( TestKeys.focusDrawerBuildLine ) ) ).data,
        'wip-v0.2.2-2026.09.30-tracking-lupin' );
    expect( tester.widget<Text>( find.byKey( const Key( TestKeys.focusDrawerBuildDetail ) ) ).data,
        '2026.10.10 build 3 · 13:12 EDT · 4c26045-dirty · push on' );
  } );

  testWidgets( 'a narrow phone overflows nothing and keeps the detail line whole', ( tester ) async {
    await pump( tester, stamped, 150 );
    expect( tester.takeException(), isNull );
    final branch = tester.widget<Text>( find.byKey( const Key( TestKeys.focusDrawerBuildLine ) ) );
    expect( branch.overflow, TextOverflow.ellipsis );
    final detail = tester.widget<Text>( find.byKey( const Key( TestKeys.focusDrawerBuildDetail ) ) );
    expect( detail.overflow, isNot( TextOverflow.ellipsis ) );
    expect( detail.data, endsWith( 'push on' ) );
    expect( tester.getSize( find.byKey( const Key( TestKeys.focusDrawerBuildDetail ) ) ).width,
        greaterThan( 0 ) );
  } );

  testWidgets( 'a detached build shows detached and the sha', ( tester ) async {
    const b = BuildInfo(
      time: '2026-10-10T13:12:00-04:00', zone: 'EDT', sha: '4c26045', number: 1, push: false,
    );
    await pump( tester, b, 320 );
    expect( tester.widget<Text>( find.byKey( const Key( TestKeys.focusDrawerBuildLine ) ) ).data,
        'detached 4c26045' );
  } );

  testWidgets( 'an unstamped build shows one line and no detail line', ( tester ) async {
    await pump( tester, const BuildInfo( push: true ), 320 );
    expect( tester.widget<Text>( find.byKey( const Key( TestKeys.focusDrawerBuildLine ) ) ).data,
        'Build: unstamped (dev run)' );
    expect( find.byKey( const Key( TestKeys.focusDrawerBuildDetail ) ), findsNothing );
  } );
}
