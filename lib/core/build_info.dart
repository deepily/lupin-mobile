import '../services/push/fcm_bootstrap.dart';

/// What the running build says about itself, as one human-readable line.
///
/// The values come from `--dart-define`s that src/scripts/build-apk-on-server.sh sets: branch,
/// date, a per-day build number, commit and push state. A build made any other way carries
/// none of them and reads as unstamped.
/// Design: src/scripts/build-apk-on-server.sh
class BuildInfo {
  /// Build time as ISO 8601 with offset, for example `2026-10-10T12:03:41-04:00`; empty when unstamped.
  final String time;

  /// Time zone abbreviation of [time], for example `EDT`; empty when not given.
  final String zone;

  /// Short commit sha; empty when unknown.
  final String sha;

  /// Whether the tree had uncommitted changes that reach the app when it was built.
  final bool dirty;

  /// Git branch the build was made from; empty when HEAD was detached.
  final String branch;

  /// Count of builds made on the build's date, starting at 1; 0 when unknown.
  final int number;

  /// Whether push wake-ups (FCM) are compiled in.
  final bool push;

  /// Creates a record from explicit values; tests use it, the app uses [current].
  const BuildInfo( {
    this.time    = '',
    this.zone    = '',
    this.sha     = '',
    this.dirty   = false,
    this.branch  = '',
    this.number  = 0,
    required this.push,
  } );

  /// The build this process is running, read from the compile-time defines.
  static const BuildInfo current = BuildInfo(
    time    : String.fromEnvironment( 'BUILD_TIME' ),
    zone    : String.fromEnvironment( 'BUILD_TZ' ),
    sha     : String.fromEnvironment( 'BUILD_SHA' ),
    dirty   : bool.fromEnvironment( 'BUILD_DIRTY' ),
    branch  : String.fromEnvironment( 'BUILD_BRANCH' ),
    number  : int.fromEnvironment( 'BUILD_NUMBER' ),
    push    : kEnableFcm,
  );

  /// True when the build script stamped this build.
  bool get isStamped => time.isNotEmpty;

  static final RegExp _isoMinute = RegExp( r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}:\d{2})' );

  /// The first drawer line: the branch built from, or `detached <sha>` when there was none.
  ///
  /// Ensures:
  ///   - an unstamped build returns `Build: unstamped (dev run)`, never blanks
  String branchLine() {
    if ( !isStamped ) return 'Build: unstamped (dev run)';
    if ( branch.isNotEmpty ) return branch;
    return sha.isEmpty ? 'detached' : 'detached $sha';
  }

  /// The second drawer line: `yyyy.mm.dd build N · HH:mm ZONE · sha · push on|off`.
  ///
  /// Ensures:
  ///   - returns an empty string for an unstamped build, which shows no second line
  ///   - unknown parts are skipped, never shown blank
  String detailLine() {
    if ( !isStamped ) return '';
    final m    = _isoMinute.firstMatch( time );
    var date   = m == null ? time : '${m.group( 1 )}.${m.group( 2 )}.${m.group( 3 )}';
    if ( number > 0 ) date = '$date build $number';
    final clock = m == null ? '' : m.group( 4 )!;
    final parts = <String>[
      date,
      if ( clock.isNotEmpty ) zone.isEmpty ? clock : '$clock $zone',
      if ( sha.isNotEmpty ) dirty ? '$sha-dirty' : sha,
      push ? 'push on' : 'push off',
    ];
    return parts.join( ' · ' );
  }

  /// Both drawer lines in one string, joined by a newline; one line when unstamped.
  String describe() => isStamped ? '${branchLine()}\n${detailLine()}' : branchLine();
}
