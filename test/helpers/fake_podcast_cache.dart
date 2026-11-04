import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show Fake;

import 'package:lupin_mobile/services/audio/podcast_cache.dart';

/// A file that only has a path, for tests that never touch the disk.
class PathFile extends Fake implements File {
  @override final String path;
  PathFile( this.path );
}

/// An in-memory [PodcastCache]: remembers fetches and never touches the disk or the network.
class FakePodcastCache extends PodcastCache {
  /// Downloaded files by name; fill it to start with a podcast already on the phone.
  final Map<String, File>   files   = {};
  /// File write times by name; a name missing here counts as the epoch.
  final Map<String, DateTime> modified = {};
  /// Saved titles by name, standing in for the title index on disk.
  final Map<String, String> savedTitles = {};
  /// Every fetch as `[serverPath, name]`, in order.
  final List<List<String>>  fetched = [];
  /// When set, [fetch] throws it instead of downloading.
  Object?                   failWith;

  FakePodcastCache() : super( ioFactory: () => throw StateError( "no io" ), dirFactory: () => throw StateError( "no dir" ) );

  @override bool isCached( String name ) => files.containsKey( name );

  @override
  Future<List<CachedPodcast>> entries() async => [
    for ( final n in files.keys ) CachedPodcast( name: n, modified: modified[ n ] ?? DateTime.fromMillisecondsSinceEpoch( 0 ) ),
  ]..sort( ( a, b ) => b.modified.compareTo( a.modified ) );

  @override Future<Map<String, String>> titles() async => Map.of( savedTitles );

  @override Future<void> saveTitle( String name, String title ) async { savedTitles[ name ] = title; }

  @override Future<File?> lookup( String name ) async => files[ name ];

  /// Every name passed to [delete], in order.
  final List<String>        deleted = [];

  @override
  Future<void> delete( String name ) async {
    deleted.add( name );
    files.remove( name );
    notifyListeners();
  }

  @override
  Future<File> fetch( String serverPath, String name ) async {
    fetched.add( [ serverPath, name ] );
    if ( failWith != null ) throw failWith!;
    final file = PathFile( "/tmp/$name.mp3" );
    files[ name ] = file;
    notifyListeners();
    return file;
  }
}
