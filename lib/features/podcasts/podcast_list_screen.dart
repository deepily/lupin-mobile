import 'package:flutter/material.dart';

import '../../core/testing/test_keys.dart';
import '../../services/audio/podcast_catalog.dart';
import '../artifacts/podcast_play.dart';

/// The Podcasts screen: recent and downloaded podcasts, newest first, each with Play.
///
/// Reads the catalog and the download folder only, so it opens and plays with no network.
class PodcastListScreen extends StatelessWidget {
  /// The podcasts to list.
  final PodcastCatalog catalog;

  /// Plays a row; null plays through [podcastPlayFor].
  final PodcastPlay? onPlay;

  /// Creates the screen.
  const PodcastListScreen( { super.key, required this.catalog, this.onPlay } );

  @override
  Widget build( BuildContext context ) {
    final play = onPlay ?? podcastPlayFor( context: context );
    return Scaffold(
      appBar: AppBar( title: const Text( "Podcasts" ) ),
      body  : ListenableBuilder(
        listenable: catalog,
        builder   : ( _, __ ) => FutureBuilder<List<PodcastListEntry>>(
          future : catalog.entries(),
          builder: ( context, snap ) {
            final rows = snap.data;
            if ( rows == null ) return const Center( child: CircularProgressIndicator() );
            if ( rows.isEmpty ) {
              return const Center( key: Key( TestKeys.podcastListEmpty ), child: Text( "No podcasts yet" ) );
            }
            return ListView.builder(
              key        : const Key( TestKeys.podcastList ),
              itemCount  : rows.length,
              itemBuilder: ( _, i ) => _row( rows[ i ], play ),
            );
          },
        ),
      ),
    );
  }

  Widget _row( PodcastListEntry e, PodcastPlay play ) {
    return ListTile(
      key     : Key( "${TestKeys.podcastListRowPrefix}${e.name}" ),
      title   : Text( e.title, maxLines: 2, overflow: TextOverflow.ellipsis ),
      subtitle: Text( _dateText( e.date ) ),
      leading : e.downloaded
          ? Icon( Icons.download_done, key: Key( "${TestKeys.podcastListDownloadedPrefix}${e.name}" ), semanticLabel: "Downloaded" )
          : const Icon( Icons.cloud_outlined, semanticLabel: "Not downloaded" ),
      trailing: IconButton(
        key      : Key( "${TestKeys.podcastListPlayPrefix}${e.name}" ),
        icon     : const Icon( Icons.play_arrow ),
        tooltip  : "Play",
        onPressed: () => play( e.audioPath, e.title ),
      ),
    );
  }

  String _dateText( DateTime d ) {
    String two( int n ) => n.toString().padLeft( 2, "0" );
    return "${d.year}-${two( d.month )}-${two( d.day )} ${two( d.hour )}:${two( d.minute )}";
  }
}
