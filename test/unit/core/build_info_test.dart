import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/build_info.dart';

/// The formatter behind the drawer's build line. `current` reads dart-defines, so the plain
/// `./flutter.sh test` run is itself the unstamped case.
void main() {
  group( 'BuildInfo.describe', () {
    test( 'a stamped build reads time, sha, version and push', () {
      const b = BuildInfo(
        time: '2026-10-10T00:13:41-04:00', zone: 'EDT', sha: '8e7132e',
        version: '0.2.2', push: true,
      );
      expect( b.describe(), 'Build 2026-10-10 00:13 EDT · 8e7132e · v0.2.2 · push on' );
    } );

    test( 'a dirty tree marks the sha', () {
      const b = BuildInfo(
        time: '2026-10-10T00:13:41-04:00', zone: 'EDT', sha: '8e7132e',
        dirty: true, version: '0.2.2', push: true,
      );
      expect( b.describe(), contains( '8e7132e-dirty' ) );
    } );

    test( 'push compiled out says push off', () {
      const b = BuildInfo( time: '2026-10-10T00:13:41-04:00', sha: 'abc1234', push: false );
      expect( b.describe(), endsWith( 'push off' ) );
    } );

    test( 'an unstamped build says so plainly', () {
      const b = BuildInfo( push: true );
      expect( b.isStamped, isFalse );
      expect( b.describe(), 'Build: unstamped (dev run)' );
    } );

    test( 'missing sha, version and zone are skipped, not shown blank', () {
      const b = BuildInfo( time: '2026-10-10T00:13:41-04:00', push: true );
      expect( b.describe(), 'Build 2026-10-10 00:13 · push on' );
    } );

    test( 'an unparseable time is shown as given, not dropped', () {
      const b = BuildInfo( time: 'yesterday', push: false );
      expect( b.describe(), 'Build yesterday · push off' );
    } );

    test( 'the unstamped plain test run reports unstamped', () {
      expect( BuildInfo.current.describe(), 'Build: unstamped (dev run)' );
    } );
  } );
}
