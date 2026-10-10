import '../services/push/fcm_bootstrap.dart';

/// What the running build says about itself, as one human-readable line.
///
/// The values come from `--dart-define`s that src/scripts/build-apk-on-server.sh sets. A build
/// made any other way carries none of them and reads as unstamped.
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

  /// Version from pubspec.yaml, for example `1.0.0+1`; empty when unknown.
  final String version;

  /// Whether push wake-ups (FCM) are compiled in.
  final bool push;

  /// Creates a record from explicit values; tests use it, the app uses [current].
  const BuildInfo( {
    this.time    = '',
    this.zone    = '',
    this.sha     = '',
    this.dirty   = false,
    this.version = '',
    required this.push,
  } );

  /// The build this process is running, read from the compile-time defines.
  static const BuildInfo current = BuildInfo(
    time    : String.fromEnvironment( 'BUILD_TIME' ),
    zone    : String.fromEnvironment( 'BUILD_TZ' ),
    sha     : String.fromEnvironment( 'BUILD_SHA' ),
    dirty   : bool.fromEnvironment( 'BUILD_DIRTY' ),
    version : String.fromEnvironment( 'BUILD_VERSION' ),
    push    : kEnableFcm,
  );

  /// True when the build script stamped this build.
  bool get isStamped => time.isNotEmpty;

  static final RegExp _isoMinute = RegExp( r'^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})' );

  /// The one line shown in the drawer.
  ///
  /// Ensures:
  ///   - an unstamped build returns `Build: unstamped (dev run)`, never blanks
  ///   - a stamped build returns `Build <time> · <sha> · v<version> · push on|off`, skipping unknown parts
  String describe() {
    if ( !isStamped ) return 'Build: unstamped (dev run)';
    final m     = _isoMinute.firstMatch( time );
    final when  = m == null ? time : '${m.group( 1 )} ${m.group( 2 )}';
    final parts = <String>[
      zone.isEmpty ? when : '$when $zone',
      if ( sha.isNotEmpty ) dirty ? '$sha-dirty' : sha,
      if ( version.isNotEmpty ) 'v$version',
      push ? 'push on' : 'push off',
    ];
    return 'Build ${parts.join( ' · ' )}';
  }
}
