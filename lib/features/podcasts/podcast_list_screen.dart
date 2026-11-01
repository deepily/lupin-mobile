import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/testing/test_keys.dart';
import '../../services/audio/podcast_catalog.dart';
import '../artifacts/podcast_play.dart';
import 'data/podcast_drive_repository.dart';

/// The Podcasts screen: the phone's podcasts, then every podcast kept in Google Drive.
///
/// The phone's own rows come from the catalog and the download folder, so they open and play
/// with no network. The Drive rows are listed live by the server; when that list fails, the
/// phone's rows still show and the Drive section says why.
class PodcastListScreen extends StatefulWidget {
  /// The podcasts to list.
  final PodcastCatalog catalog;

  /// Plays a row; null plays through [podcastPlayFor].
  final PodcastPlay? onPlay;

  /// Lists the Drive podcasts; null uses the registered repository.
  ///
  /// With none registered, the screen shows no Drive section.
  final PodcastDriveRepository? drive;

  /// Creates the screen.
  const PodcastListScreen( { super.key, required this.catalog, this.onPlay, this.drive } );

  @override
  State<PodcastListScreen> createState() => _PodcastListScreenState();
}

class _PodcastListScreenState extends State<PodcastListScreen> {
  List<PodcastListEntry>?   _rows;
  List<DrivePodcastFolder>? _driveFolders;
  String?                   _driveError;
  PodcastDriveRepository?   _drive;

  @override
  void initState() {
    super.initState();
    _drive = widget.drive ?? ( ServiceLocator.isRegistered<PodcastDriveRepository>() ? ServiceLocator.get<PodcastDriveRepository>() : null );
    widget.catalog.addListener( _reload );
    _reload();
    unawaited( _reloadDrive() );
  }

  @override
  void dispose() {
    widget.catalog.removeListener( _reload );
    super.dispose();
  }

  /// Reloads the rows; the old rows stay on screen until the new ones arrive.
  ///
  /// A failed read shows the empty state instead of a spinner that never stops.
  Future<void> _reload() async {
    List<PodcastListEntry> rows;
    try {
      rows = await widget.catalog.entries();
    } catch ( e ) {
      debugPrint( "[PodcastList] could not load the list: $e" );
      rows = const [];
    }
    if ( mounted ) setState( () => _rows = rows );
  }

  /// Reloads the Drive section; a failure keeps the last good list and shows the reason.
  Future<void> _reloadDrive() async {
    final drive = _drive;
    if ( drive == null ) return;
    try {
      final folders = await drive.list();
      if ( mounted ) setState( () { _driveFolders = folders; _driveError = null; } );
    } on PodcastDriveException catch ( e ) {
      debugPrint( "[PodcastList] Drive list failed: $e" );
      if ( mounted ) setState( () => _driveError = e.message );
    }
  }

  Future<void> _refreshAll() => Future.wait( [ _reload(), _reloadDrive() ] );

  @override
  Widget build( BuildContext context ) {
    final play = widget.onPlay ?? podcastPlayFor( context: context );
    final rows = _rows;
    return Scaffold(
      appBar: AppBar( title: const Text( "Podcasts" ) ),
      body  : rows == null
          ? const Center( child: CircularProgressIndicator() )
          : _drive == null
              ? _phoneOnly( rows, play )
              : RefreshIndicator( onRefresh: _refreshAll, child: _withDrive( rows, play ) ),
    );
  }

  Widget _phoneOnly( List<PodcastListEntry> rows, PodcastPlay play ) {
    if ( rows.isEmpty ) return const Center( key: Key( TestKeys.podcastListEmpty ), child: Text( "No podcasts yet" ) );
    return ListView.builder(
      key        : const Key( TestKeys.podcastList ),
      itemCount  : rows.length,
      itemBuilder: ( _, i ) => _row( rows[ i ], play ),
    );
  }

  Widget _withDrive( List<PodcastListEntry> rows, PodcastPlay play ) {
    Future<void> drivePlay( String url, String title ) async {
      await widget.catalog.rememberTitle( url, title );
      await play( url, title );
    }
    final children = <Widget>[
      if ( rows.isEmpty )
        const ListTile( key: Key( TestKeys.podcastListEmpty ), title: Text( "No podcasts on this phone yet" ) ),
      for ( final r in rows ) _row( r, play ),
      _header(),
      ..._driveRows( drivePlay ),
    ];
    return ListView( key: const Key( TestKeys.podcastList ), physics: const AlwaysScrollableScrollPhysics(), children: children );
  }

  Widget _header() {
    return Padding(
      key    : const Key( TestKeys.podcastDriveHeader ),
      padding: const EdgeInsets.fromLTRB( 16, 24, 16, 4 ),
      child  : Text( "Google Drive", style: Theme.of( context ).textTheme.titleSmall ),
    );
  }

  List<Widget> _driveRows( PodcastPlay play ) {
    final folders = _driveFolders;
    final error   = _driveError;
    final out     = <Widget>[];
    if ( error != null ) {
      out.add( ListTile(
        key     : const Key( TestKeys.podcastDriveError ),
        leading : const Icon( Icons.cloud_off ),
        title   : Text( error ),
        subtitle: const Text( "Pull down to try again" ),
      ) );
    }
    if ( folders == null ) {
      if ( error == null ) out.add( const Padding( padding: EdgeInsets.all( 16 ), child: Center( child: CircularProgressIndicator() ) ) );
      return out;
    }
    final audio = [ for ( final f in folders ) for ( final file in f.files.where( ( x ) => x.isAudio ) ) ( f, file ) ];
    if ( audio.isEmpty && error == null ) {
      out.add( const ListTile( key: Key( TestKeys.podcastDriveEmpty ), title: Text( "No podcasts in Drive yet" ) ) );
    }
    for ( final ( folder, file ) in audio ) {
      final many  = folder.files.where( ( x ) => x.isAudio ).length > 1;
      final title = many ? "${folder.title} (${file.name})" : folder.title;
      out.add( ListTile(
        key     : Key( "${TestKeys.podcastDriveRowPrefix}${folder.jobFolder}/${file.driveFileId}" ),
        leading : const Icon( Icons.cloud_outlined, semanticLabel: "In Google Drive" ),
        title   : Text( title, maxLines: 2, overflow: TextOverflow.ellipsis ),
        subtitle: Text( folder.created == null ? folder.jobFolder : _dateText( folder.created! ) ),
        trailing: IconButton(
          key      : Key( "${TestKeys.podcastDrivePlayPrefix}${folder.jobFolder}/${file.driveFileId}" ),
          icon     : const Icon( Icons.play_arrow ),
          tooltip  : "Play",
          onPressed: () => play( file.streamUrl, title ),
        ),
      ) );
    }
    return out;
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
