import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../services/artifacts/io_file_service.dart';

/// Metadata card + open-in-external-app for PPTX/PDF slide decks.
class SlideDeckViewer extends StatefulWidget {
  final String jobId;
  final String deckPath; // server-side path for /api/io/file?path=...

  const SlideDeckViewer( {
    super.key,
    required this.jobId,
    required this.deckPath,
  } );

  @override
  State<SlideDeckViewer> createState() => _SlideDeckViewerState();
}

class _SlideDeckViewerState extends State<SlideDeckViewer> {
  bool _loading = false;

  Future<void> _open() async {
    setState( () => _loading = true );
    try {
      final svc  = ServiceLocator.instance<IoFileService>();
      final file = await svc.downloadToCache( widget.deckPath, '${widget.jobId}.pptx' );
      await svc.openExternalApp( file );
    } catch ( e ) {
      if ( mounted ) {
        ScaffoldMessenger.of( context ).showSnackBar(
          SnackBar( content: Text( 'Open failed: $e' ), backgroundColor: Colors.red ),
        );
      }
    } finally {
      if ( mounted ) setState( () => _loading = false );
    }
  }

  Future<void> _share() async {
    setState( () => _loading = true );
    try {
      final svc  = ServiceLocator.instance<IoFileService>();
      final file = await svc.downloadToCache( widget.deckPath, '${widget.jobId}.pptx' );
      await svc.shareToExternalApp( file );
    } catch ( e ) {
      if ( mounted ) {
        ScaffoldMessenger.of( context ).showSnackBar(
          SnackBar( content: Text( 'Share failed: $e' ), backgroundColor: Colors.red ),
        );
      }
    } finally {
      if ( mounted ) setState( () => _loading = false );
    }
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title  : Text( 'Slide Deck — ${widget.jobId}' ),
        actions: [
          IconButton(
            icon     : const Icon( Icons.share_outlined ),
            tooltip  : 'Share',
            onPressed: _loading ? null : _share,
          ),
        ],
      ),
      body: Padding( padding: const EdgeInsets.all( 24 ), child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon( Icons.slideshow_outlined, size: 80 ),
          const SizedBox( height: 16 ),
          Text(
            widget.jobId,
            style: Theme.of( context ).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox( height: 8 ),
          Text(
            widget.deckPath,
            style: Theme.of( context ).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox( height: 32 ),
          FilledButton.icon(
            onPressed: _loading ? null : _open,
            icon : _loading
                ? const SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2 ) )
                : const Icon( Icons.open_in_new_outlined ),
            label: Text( _loading ? 'Loading…' : 'Open in App' ),
          ),
        ],
      ) ),
    );
  }
}
