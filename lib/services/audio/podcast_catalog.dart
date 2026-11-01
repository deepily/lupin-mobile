import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/artifacts/podcast_play.dart';
import '../../features/notifications/presentation/podcast_done_actions.dart';
import 'podcast_cache.dart';

/// One row of the Podcasts list.
class PodcastListEntry {
  /// The cache file name and track id; two entries never share one.
  final String name;

  /// The bare server path of the audio, which [PodcastPlayerService.play] takes.
  final String audioPath;

  /// What the row shows as its title.
  final String title;

  /// When the podcast finished, or when its file was written when no notification is held.
  final DateTime date;

  /// True when the file is on the phone.
  final bool downloaded;

  /// Creates one row.
  const PodcastListEntry( {
    required this.name,
    required this.audioPath,
    required this.title,
    required this.date,
    required this.downloaded,
  } );
}

/// The podcasts the Podcasts list shows: finished ones heard of, plus downloads.
///
/// Notifications are held in memory only. Each title is also saved next to its file,
/// so after a restart the list still shows real titles. A file with no saved title uses its name.
class PodcastCatalog extends ChangeNotifier {
  final PodcastCache _cache;
  final Map<String, PodcastListEntry> _held = {};

  /// Creates the catalog over [cache].
  PodcastCatalog( PodcastCache cache ) : _cache = cache {
    _cache.addListener( notifyListeners );
  }

  /// Remembers the audio a podcast-done notification links.
  ///
  /// Requires:
  ///   - [abstractText] may be null or hold no audio link
  ///
  /// Ensures:
  ///   - each title is saved in the cache's title index
  ///   - one entry per audio link, titled [title] when it is not blank, else the link's label
  ///   - a second call for the same audio replaces the first
  ///   - notifies listeners only when an entry was added
  void record( String? abstractText, { String? title, required DateTime at } ) {
    final audio = parsePodcastAudio( abstractText );
    if ( audio.isEmpty ) return;
    for ( final item in audio ) {
      final name = podcastCacheName( item.url );
      _held[ name ] = PodcastListEntry(
        name      : name,
        audioPath : audioPathOf( item.url ),
        title     : ( title != null && title.trim().isNotEmpty ) ? title.trim() : item.label,
        date      : at,
        downloaded: false,
      );
      if ( _held[ name ]!.title.isNotEmpty ) unawaited( _cache.saveTitle( name, _held[ name ]!.title ) );
    }
    notifyListeners();
  }

  /// Saves [title] for the audio at [audioPath], so its download lists under that title.
  ///
  /// Used for podcasts played from Drive, which arrive with no notification.
  ///
  /// Ensures:
  ///   - a blank [title] saves nothing
  Future<void> rememberTitle( String audioPath, String title ) async {
    if ( title.trim().isEmpty ) return;
    await _cache.saveTitle( podcastCacheName( audioPath ), title.trim() );
  }

  /// The list rows, newest first.
  ///
  /// Ensures:
  ///   - a downloaded file with no held notification is listed, titled from the saved index, else its file name
  ///   - dated by its file time
  ///   - a held notification whose file is not downloaded is listed with downloaded false
  ///   - makes no network call
  Future<List<PodcastListEntry>> entries() async {
    final merged = <String, PodcastListEntry>{};
    final saved  = await _cache.titles();
    for ( final file in await _cache.entries() ) {
      final path = Uri.decodeComponent( file.name );
      merged[ file.name ] = PodcastListEntry(
        name: file.name, audioPath: path, title: saved[ file.name ] ?? _titleOf( path ), date: file.modified, downloaded: true,
      );
    }
    for ( final held in _held.values ) {
      final onDisk = merged[ held.name ];
      merged[ held.name ] = PodcastListEntry(
        name: held.name, audioPath: held.audioPath, title: held.title, date: held.date, downloaded: onDisk != null,
      );
    }
    return merged.values.toList()..sort( ( a, b ) => b.date.compareTo( a.date ) );
  }

  String _titleOf( String path ) {
    final base = path.substring( path.lastIndexOf( "/" ) + 1 );
    final dot  = base.lastIndexOf( "." );
    final stem = dot > 0 ? base.substring( 0, dot ) : base;
    return stem.isEmpty ? "Podcast" : stem;
  }

  @override
  void dispose() {
    _cache.removeListener( notifyListeners );
    super.dispose();
  }
}
