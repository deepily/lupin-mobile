import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/build_info.dart';

/// The formatter behind the drawer's build line. `current` reads dart-defines, so the plain
/// `./flutter.sh test` run is itself the unstamped case.
void main() {
  group( 'BuildInfo.describe', () {
    test( 'a stamped build reads time, sha, version and push', () {
      const b = BuildInfo(
        time: '2026-10-10T00:13:41-04:00', zone: 'EDT', sha: '8e7132e',
        branch: 'wip-v0.2.2-2026.09.30-tracking-lupin', number: 3, push: true,
      );
      expect( b.describe(),
          'wip-v0.2.2-2026.09.30-tracking-lupin\n2026.10.10 build 3 · 00:13 EDT · 8e7132e · push on' );
      expect( b.describe(), isNot( contains( '0.2.2 ·' ) ) );
    } );

    test( 'a dirty tree marks the sha', () {
      const b = BuildInfo(
        time: '2026-10-10T00:13:41-04:00', zone: 'EDT', sha: '8e7132e',
        dirty: true, push: true,
      );
      expect( b.describe(), contains( '8e7132e-dirty' ) );
    } );

    test( 'push compiled out says push off', () {
      const b = BuildInfo( time: '2026-10-10T00:13:41-04:00', sha: 'abc1234', push: false );
      expect( b.describe(), endsWith( 'push off' ) );
      expect( b.detailLine(), endsWith( 'push off' ) );
    } );

    test( 'an unstamped build says so plainly', () {
      const b = BuildInfo( push: true );
      expect( b.isStamped, isFalse );
      expect( b.describe(), 'Build: unstamped (dev run)' );
    } );

    test( 'missing sha, version and zone are skipped, not shown blank', () {
      const b = BuildInfo( time: '2026-10-10T00:13:41-04:00', push: true );
      expect( b.detailLine(), '2026.10.10 · 00:13 · push on' );
      expect( b.branchLine(), 'detached' );
    } );

    test( 'an unparseable time is shown as given, not dropped', () {
      const b = BuildInfo( time: 'yesterday', push: false );
      expect( b.detailLine(), 'yesterday · push off' );
    } );

    test( 'a branch with slashes is shown whole on the first line', () {
      const b = BuildInfo(
        time: '2026-10-10T13:12:00-04:00', zone: 'EDT', sha: '4c26045',
        branch: 'fix/fcm-review-findings', number: 1, push: true,
      );
      expect( b.branchLine(), 'fix/fcm-review-findings' );
      expect( b.detailLine(), '2026.10.10 build 1 · 13:12 EDT · 4c26045 · push on' );
    } );

    test( 'a detached HEAD shows detached plus the sha in place of a branch', () {
      const b = BuildInfo(
        time: '2026-10-10T13:12:00-04:00', zone: 'EDT', sha: '4c26045', number: 2, push: true,
      );
      expect( b.branchLine(), 'detached 4c26045' );
      expect( b.detailLine(), '2026.10.10 build 2 · 13:12 EDT · 4c26045 · push on' );
    } );

    test( 'an unknown build number is skipped, not shown as zero', () {
      const b = BuildInfo( time: '2026-10-10T13:12:00-04:00', branch: 'main', push: true );
      expect( b.detailLine(), '2026.10.10 · 13:12 · push on' );
    } );

    test( 'an unstamped build has no detail line', () {
      const b = BuildInfo( push: true );
      expect( b.branchLine(), 'Build: unstamped (dev run)' );
      expect( b.detailLine(), isEmpty );
    } );

    test( 'the unstamped plain test run reports unstamped', () {
      expect( BuildInfo.current.describe(), 'Build: unstamped (dev run)' );
    } );
  } );
}
