import 'package:flutter/material.dart';

import '../../core/testing/test_keys.dart';
import '../../services/audio/podcast_catalog.dart';
import '../artifacts/podcast_play.dart';

/// The Podcasts screen: recent and downloaded podcasts, newest first, each with Play.
///
/// Reads the catalog and the download folder only, so it opens and plays with no network.
class PodcastListScreen extends StatefulWidget {
  /// The podcasts to list.
  final PodcastCatalog catalog;

  /// Plays a row; null plays through [podcastPlayFor].
  final PodcastPlay? onPlay;

  /// Creates the screen.
  const PodcastListScreen( { super.key, required this.catalog, this.onPlay } );

  @override
  State<PodcastListScreen> createState() => _PodcastListScreenState();
}

class _PodcastListScreenState extends State<PodcastListScreen> {
  List<PodcastListEntry>? _rows;

  @override
  void initState() {
    super.initState();
    widget.catalog.addListener( _reload );
    _reload();
  }

  @override
  void dispose() {
    widget.catalog.removeListener( _reload );
    super.dispose();
  }

  /// Reloads the rows; the old rows stay on screen until the new ones arrive.
  Future<void> _reload() async {
    final rows = await widget.catalog.entries();
    if ( mounted ) setState( () => _rows = rows );
  }

  @override
  Widget build( BuildContext context ) {
    final play = widget.onPlay ?? podcastPlayFor( context: context );
    final rows = _rows;
    return Scaffold(
      appBar: AppBar( title: const Text( "Podcasts" ) ),
      body  : rows == null
          ? const Center( child: CircularProgressIndicator() )
          : rows.isEmpty
              ? const Center( key: Key( TestKeys.podcastListEmpty ), child: Text( "No podcasts yet" ) )
              : ListView.builder(
                  key        : const Key( TestKeys.podcastList ),
                  itemCount  : rows.length,
                  itemBuilder: ( _, i ) => _row( rows[ i ], play ),
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
