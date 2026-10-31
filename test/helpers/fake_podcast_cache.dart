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
  /// Every fetch as `[serverPath, name]`, in order.
  final List<List<String>>  fetched = [];
  /// When set, [fetch] throws it instead of downloading.
  Object?                   failWith;

  FakePodcastCache() : super( ioFactory: () => throw StateError( "no io" ), dirFactory: () => throw StateError( "no dir" ) );

  @override bool isCached( String name ) => files.containsKey( name );

  @override Future<File?> lookup( String name ) async => files[ name ];

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
