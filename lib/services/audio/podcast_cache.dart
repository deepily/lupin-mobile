import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../artifacts/io_file_service.dart';

/// The file in the podcast folder that maps a cache name to its title.
const String kPodcastTitleIndex = "titles.json";

/// How long a downloaded podcast is kept before startup deletes it.
const Duration kPodcastCacheMaxAge = Duration( days: 30 );

/// The folder downloaded podcasts live in: `podcasts` under the app's support directory.
///
/// Unlike the temporary directory, the system does not clear it when space runs low.
Future<Directory> podcastCacheDirectory() async =>
    Directory( "${( await getApplicationSupportDirectory() ).path}/podcasts" );

/// One finished download: its cache [name] and when its file was written.
class CachedPodcast {
  /// The cache file name without `.mp3`, the percent-encoded server path.
  final String name;

  /// When the file was written.
  final DateTime modified;

  /// Creates one entry.
  const CachedPodcast( { required this.name, required this.modified } );
}

/// Podcasts downloaded to the phone, so they play again without a network.
///
/// A file counts as downloaded only once it is whole: a download goes to a `.part` file and is
/// renamed to `<name>.mp3` when it finishes. The set of names is a [ChangeNotifier] so a card
/// or the mini-player can show a downloaded marker.
class PodcastCache extends ChangeNotifier {
  final IoFileService Function()    _ioFactory;
  final Future<Directory> Function() _dirFactory;
  final DateTime Function()          _now;

  final Set<String>                  _names    = {};
  final Map<String, Future<File>>    _inFlight = {};
  Future<void>                       _titleWrites = Future<void>.value();

  /// Creates the cache; [ioFactory] and [dirFactory] run on first use, and [now] is the clock.
  PodcastCache( {
    required IoFileService Function()     ioFactory,
    required Future<Directory> Function() dirFactory,
    DateTime Function()                   now = DateTime.now,
  } ) : _ioFactory  = ioFactory,
        _dirFactory = dirFactory,
        _now        = now;

  /// True when the podcast called [name] is whole on disk and known to this cache.
  bool isCached( String name ) => _names.contains( name );

  /// Reads the folder and learns which podcasts are already on disk.
  ///
  /// Ensures:
  ///   - only finished `.mp3` files are listed; `.part` leftovers from a dropped download are deleted
  Future<void> load() async {
    final dir = await _dir();
    _names.clear();
    await for ( final entry in dir.list() ) {
      if ( entry is! File ) continue;
      final base = _baseName( entry.path );
      if ( base.endsWith( ".part" ) ) {
        await entry.delete();
      } else if ( base.endsWith( ".mp3" ) ) {
        _names.add( base.substring( 0, base.length - 4 ) );
      }
    }
    notifyListeners();
  }

  /// The downloaded file for [name], or null when it is not downloaded.
  ///
  /// Makes no network call.
  Future<File?> lookup( String name ) async {
    final file = File( "${( await _dir() ).path}/$name.mp3" );
    if ( await file.exists() ) {
      if ( _names.add( name ) ) notifyListeners();
      return file;
    }
    if ( _names.remove( name ) ) notifyListeners();
    return null;
  }

  /// The saved titles by cache name; empty when none are saved or the index is unreadable.
  ///
  /// Reads the folder only; makes no network call.
  Future<Map<String, String>> titles() async {
    try {
      final file = File( "${( await _dir() ).path}/$kPodcastTitleIndex" );
      if ( !await file.exists() ) return {};
      final decoded = jsonDecode( await file.readAsString() );
      if ( decoded is! Map ) return {};
      return { for ( final e in decoded.entries ) if ( e.value is String ) e.key.toString(): e.value as String };
    } catch ( e ) {
      debugPrint( "[PodcastCache] title index unreadable: $e" );
      return {};
    }
  }

  /// Saves [title] for the podcast called [name], next to its file.
  ///
  /// Ensures:
  ///   - saves are applied one after another, so none overwrites another
  ///   - never throws; a failed save is printed and the list falls back to the file name
  Future<void> saveTitle( String name, String title ) {
    return _titleWrites = _titleWrites.then( ( _ ) async {
      try {
        final all = await titles();
        if ( all[ name ] == title ) return;
        all[ name ] = title;
        await File( "${( await _dir() ).path}/$kPodcastTitleIndex" ).writeAsString( jsonEncode( all ) );
      } catch ( e ) {
        debugPrint( "[PodcastCache] title save failed: $e" );
      }
    } );
  }

  /// Every downloaded podcast with the time its file was written, newest first.
  ///
  /// Reads the folder only; makes no network call.
  Future<List<CachedPodcast>> entries() async {
    final found = <CachedPodcast>[];
    await for ( final entry in ( await _dir() ).list() ) {
      if ( entry is! File ) continue;
      final base = _baseName( entry.path );
      if ( !base.endsWith( ".mp3" ) ) continue;
      found.add( CachedPodcast( name: base.substring( 0, base.length - 4 ), modified: await entry.lastModified() ) );
    }
    found.sort( ( a, b ) => b.modified.compareTo( a.modified ) );
    return found;
  }

  /// Downloads the server file at [serverPath] as [name] and returns it.
  ///
  /// Ensures:
  ///   - the file appears under its final name only when the whole download finished
  ///   - a failed or dropped download leaves no file behind and is rethrown
  ///   - two calls for the same [name] share one download
  Future<File> fetch( String serverPath, String name ) {
    return _inFlight.putIfAbsent( name, () => _download( serverPath, name ).whenComplete( () { _inFlight.remove( name ); } ) );
  }

  /// Deletes every download older than [age] and returns how many it removed.
  ///
  /// Age is the time since the file was written. A half-finished `.part` file that old goes too.
  Future<int> deleteOlderThan( Duration age ) async {
    final cutoff  = _now().subtract( age );
    var   removed = 0;
    await for ( final entry in ( await _dir() ).list() ) {
      if ( entry is! File ) continue;
      if ( _baseName( entry.path ) == kPodcastTitleIndex ) continue;
      if ( ( await entry.lastModified() ).isBefore( cutoff ) ) {
        await entry.delete();
        final base = _baseName( entry.path );
        if ( base.endsWith( ".mp3" ) ) _names.remove( base.substring( 0, base.length - 4 ) );
        removed++;
      }
    }
    if ( removed > 0 ) notifyListeners();
    return removed;
  }

  Future<File> _download( String serverPath, String name ) async {
    final dir   = await _dir();
    final part  = File( "${dir.path}/$name.mp3.part" );
    final whole = File( "${dir.path}/$name.mp3" );
    try {
      await _ioFactory().downloadTo( serverPath, part );
      await part.rename( whole.path );
    } catch ( _ ) {
      if ( await part.exists() ) await part.delete();
      rethrow;
    }
    _names.add( name );
    notifyListeners();
    return whole;
  }

  Future<Directory> _dir() async {
    final dir = await _dirFactory();
    await dir.create( recursive: true );
    return dir;
  }

  String _baseName( String path ) => path.substring( path.lastIndexOf( "/" ) + 1 );
}

/// Deletes downloads older than [kPodcastCacheMaxAge] at startup, then learns what is left.
///
/// Ensures:
///   - never throws; a failure is printed and the cache simply starts empty
Future<void> preparePodcastCache( PodcastCache cache ) async {
  try {
    await cache.deleteOlderThan( kPodcastCacheMaxAge );
    await cache.load();
  } catch ( e ) {
    debugPrint( "[PodcastCache] startup cleanup failed: $e" );
  }
}
