import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../services/artifacts/io_file_service.dart';

/// Streams and plays an MP3 audio artifact from /api/io/file.
///
/// Uses system share sheet for download/share — no native audio player
/// dependency needed for the prototype since audioplayers setup is
/// non-trivial; sharing the file lets the user play in any audio app.
class AudioArtifactPlayer extends StatefulWidget {
  final String jobId;
  final String audioPath; // server-side path passed to /api/io/file?path=...

  const AudioArtifactPlayer( {
    super.key,
    required this.jobId,
    required this.audioPath,
  } );

  @override
  State<AudioArtifactPlayer> createState() => _AudioArtifactPlayerState();
}

class _AudioArtifactPlayerState extends State<AudioArtifactPlayer> {
  bool _downloading = false;

  Future<void> _downloadAndShare() async {
    setState( () => _downloading = true );
    try {
      final svc  = ServiceLocator.instance<IoFileService>();
      final file = await svc.downloadToCache( widget.audioPath, '${widget.jobId}.mp3' );
      await svc.shareToExternalApp( file );
    } catch ( e ) {
      if ( mounted ) {
        ScaffoldMessenger.of( context ).showSnackBar(
          SnackBar( content: Text( 'Download failed: $e' ), backgroundColor: Colors.red ),
        );
      }
    } finally {
      if ( mounted ) setState( () => _downloading = false );
    }
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: Text( 'Audio — ${widget.jobId}' ) ),
      body: Padding( padding: const EdgeInsets.all( 24 ), child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon( Icons.audiotrack_outlined, size: 80 ),
          const SizedBox( height: 16 ),
          Text(
            widget.jobId,
            style: Theme.of( context ).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox( height: 8 ),
          Text(
            'Download the audio file to listen in your preferred audio player.',
            style: Theme.of( context ).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox( height: 32 ),
          FilledButton.icon(
            onPressed: _downloading ? null : _downloadAndShare,
            icon : _downloading
                ? const SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2 ) )
                : const Icon( Icons.download_outlined ),
            label: Text( _downloading ? 'Downloading…' : 'Download & Share' ),
          ),
        ],
      ) ),
    );
  }
}
