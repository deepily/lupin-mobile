import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/testing/test_keys.dart';
import '../../services/audio/podcast_cache.dart';
import '../../services/audio/podcast_catalog.dart';
import '../../services/audio/podcast_link.dart';
import '../artifacts/podcast_download_sheet.dart';
import '../artifacts/podcast_play.dart';
import 'data/podcast_drive_repository.dart';

/// The Podcasts screen: the phone's podcasts, then every podcast kept in Google Drive.
///
/// The phone's own rows come from the catalog and the download folder, so they open and play
/// with no network. The Drive rows are listed live by the server; when that list fails, the
/// phone's rows still show and the Drive section says why.
///
/// Each Drive row has a download button that keeps the podcast on the phone, so Play needs no
/// network later. On mobile data it asks first, with the same sheet Play uses.
class PodcastListScreen extends StatefulWidget {
  /// The podcasts to list.
  final PodcastCatalog catalog;

  /// Plays a row; null plays through [podcastPlayFor].
  final PodcastPlay? onPlay;

  /// Lists the Drive podcasts; null uses the registered repository.
  ///
  /// With none registered, the screen shows no Drive section.
  final PodcastDriveRepository? drive;

  /// Keeps downloaded Drive podcasts; null uses the registered cache.
  ///
  /// With none registered, the Drive rows have no download button.
  final PodcastCache? cache;

  /// Reads how the phone is connected before a download; null reads the real connection.
  final Future<PodcastLink> Function()? linkProbe;

  /// Creates the screen.
  const PodcastListScreen( { super.key, required this.catalog, this.onPlay, this.drive, this.cache, this.linkProbe } );

  @override
  State<PodcastListScreen> createState() => _PodcastListScreenState();
}

class _PodcastListScreenState extends State<PodcastListScreen> {
  List<PodcastListEntry>?   _rows;
  List<DrivePodcastFolder>? _driveFolders;
  String?                   _driveError;
  PodcastDriveRepository?   _drive;
  PodcastCache?             _cache;
  final Set<String>         _busy        = {};
  final Set<String>         _downloading = {};

  @override
  void initState() {
    super.initState();
    _drive = widget.drive ?? ( ServiceLocator.isRegistered<PodcastDriveRepository>() ? ServiceLocator.get<PodcastDriveRepository>() : null );
    _cache = widget.cache ?? ( ServiceLocator.isRegistered<PodcastCache>() ? ServiceLocator.get<PodcastCache>() : null );
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

  /// Downloads the Drive podcast at [url] onto the phone under [title].
  ///
  /// Ensures:
  ///   - on Wi-Fi it downloads at once; on mobile data only after the listener taps Download
  ///   - with no connection, an unreadable connection, or a failed download, a message says so
  ///     and nothing is kept
  ///   - the title is saved, so the phone's list shows it
  ///   - a second tap before the first one ends does nothing
  ///   - the row shows a spinner while the file downloads
  Future<void> _download( PodcastCache cache, String url, String title ) async {
    final name = podcastCacheName( url );
    if ( !_busy.add( name ) ) return;
    final messenger = ScaffoldMessenger.of( context );
    try {
      final PodcastLink link;
      try {
        link = await ( widget.linkProbe ?? currentPodcastLink )();
      } catch ( e ) {
        debugPrint( "[PodcastList] connection check failed: $e" );
        messenger.showSnackBar( const SnackBar( content: Text( "Could not check the connection, so nothing downloaded." ) ) );
        return;
      }
      if ( link == PodcastLink.offline ) {
        messenger.showSnackBar( const SnackBar( content: Text( "There is no connection, so nothing can download." ) ) );
        return;
      }
      if ( link == PodcastLink.metered ) {
        if ( !mounted ) return;
        if ( !await showPodcastDataSheet( context, title ) ) return;
      }
      if ( !mounted ) return;
      setState( () => _downloading.add( name ) );
      await widget.catalog.rememberTitle( url, title );
      await cache.fetch( audioPathOf( url ), name );
    } catch ( e ) {
      debugPrint( "[PodcastList] download of $url failed: $e" );
      messenger.showSnackBar( SnackBar( content: Text( "Could not download $title. Tap download to try again." ) ) );
    } finally {
      _busy.remove( name );
      if ( mounted ) setState( () => _downloading.remove( name ) );
    }
  }

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
      final many    = folder.files.where( ( x ) => x.isAudio ).length > 1;
      final title   = many ? "${folder.title} (${file.name})" : folder.title;
      final id      = "${folder.jobFolder}/${file.driveFileId}";
      final onPhone = _cache?.isCached( podcastCacheName( file.streamUrl ) ) ?? false;
      out.add( ListTile(
        key     : Key( "${TestKeys.podcastDriveRowPrefix}$id" ),
        leading : onPhone
            ? Icon( Icons.download_done, key: Key( "${TestKeys.podcastDriveDownloadedPrefix}$id" ), semanticLabel: "On this phone" )
            : const Icon( Icons.cloud_outlined, semanticLabel: "In Google Drive" ),
        title   : Text( title, maxLines: 2, overflow: TextOverflow.ellipsis ),
        subtitle: Text( folder.created == null ? folder.jobFolder : _dateText( folder.created! ) ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children    : [
            if ( !onPhone ) _downloadButton( id, file.streamUrl, title ),
            IconButton(
              key      : Key( "${TestKeys.podcastDrivePlayPrefix}$id" ),
              icon     : const Icon( Icons.play_arrow ),
              tooltip  : "Play",
              onPressed: () => play( file.streamUrl, title ),
            ),
          ],
        ),
      ) );
    }
    return out;
  }

  /// The download button of the Drive row [id], or a spinner while it downloads.
  ///
  /// Nothing when there is no cache to download into.
  Widget _downloadButton( String id, String url, String title ) {
    final cache = _cache;
    if ( cache == null ) return const SizedBox.shrink();
    if ( _downloading.contains( podcastCacheName( url ) ) ) {
      return SizedBox(
        key   : Key( "${TestKeys.podcastDriveDownloadingPrefix}$id" ),
        width : 48,
        height: 48,
        child : const Padding( padding: EdgeInsets.all( 14 ), child: CircularProgressIndicator( strokeWidth: 2, semanticsLabel: "Downloading" ) ),
      );
    }
    return IconButton(
      key      : Key( "${TestKeys.podcastDriveDownloadPrefix}$id" ),
      icon     : const Icon( Icons.download ),
      tooltip  : "Download to this phone",
      onPressed: () => _download( cache, url, title ),
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
