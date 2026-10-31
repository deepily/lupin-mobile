import 'package:flutter/material.dart';

import '../../core/testing/test_keys.dart';
import '../../services/audio/podcast_player_service.dart';

/// Slim bar at the bottom of every screen showing the podcast that is loaded.
///
/// Hidden while nothing is loaded. Play/pause and close act on the app-wide
/// [PodcastPlayerService], so they work from any screen.
class MiniPlayerBar extends StatelessWidget {
  /// The service the bar mirrors and controls.
  final PodcastPlayerService service;

  /// Creates the bar for [service].
  const MiniPlayerBar( {super.key, required this.service} );

  @override
  Widget build( BuildContext context ) {
    return ListenableBuilder( listenable: service, builder: _build );
  }

  Widget _build( BuildContext context, Widget? _ ) {
    if ( !service.hasTrack ) return const SizedBox.shrink();
    final totalMs = service.duration.inMilliseconds;
    final fraction = totalMs == 0 ? 0.0 : ( service.position.inMilliseconds / totalMs ).clamp( 0.0, 1.0 );
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator( value: fraction, minHeight: 2 ),
            ListTile(
              dense  : true,
              leading: const Icon( Icons.audiotrack_outlined ),
              title  : Text( service.title ?? "", maxLines: 1, overflow: TextOverflow.ellipsis ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key      : const Key( TestKeys.miniPlayerToggle ),
                    // No tooltip: this bar sits above the Navigator, where there is no Overlay for it.
                    icon     : Icon( service.isPlaying ? Icons.pause : Icons.play_arrow, semanticLabel: service.isPlaying ? "Pause" : "Play" ),
                    onPressed: service.isPlaying ? service.pause : service.resume,
                  ),
                  IconButton(
                    key      : const Key( TestKeys.miniPlayerClose ),
                    icon     : const Icon( Icons.close, semanticLabel: "Stop" ),
                    onPressed: service.stop,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
