import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../../artifacts/podcast_play.dart';

/// One audio file named in a done abstract.
class PodcastAudio {
  /// The language label, such as "Mexican Spanish"; "Podcast" when the line has none.
  final String label;

  /// The bare server path of the audio file, such as `io/podcast/a.mp3`.
  final String url;

  /// Creates one playable entry.
  const PodcastAudio( { required this.label, required this.url } );
}

final RegExp _audioLink  = RegExp( r'\((?:/app/audio|/api/io/file)\?path=([^)\s&]+)' );
final RegExp _lineLabel  = RegExp( r'^\*\*(.+?)\*\*' );

/// The audio files a done abstract links, one per line, in order.
///
/// Requires:
///   - [abstractText] may be null
///
/// Ensures:
///   - a line yields an entry when it holds a `/app/audio?path=` or `/api/io/file?path=` link
///   - the entry's label is the line's leading bold text, else "Podcast"
///   - null, empty and link-free text yield an empty list
List<PodcastAudio> parsePodcastAudio( String? abstractText ) {
  if ( abstractText == null || abstractText.isEmpty ) return const [];
  final found = <PodcastAudio>[];
  for ( final line in abstractText.split( "\n" ) ) {
    final hit = _audioLink.firstMatch( line );
    if ( hit == null ) continue;
    found.add( PodcastAudio(
      label: _lineLabel.firstMatch( line )?.group( 1 ) ?? "Podcast",
      url  : Uri.decodeComponent( hit.group( 1 )! ),
    ) );
  }
  return found;
}

/// Play buttons for a finished podcast's card, from the audio links in its abstract.
///
/// Renders nothing when the abstract names no audio, so any card can carry it.
class PodcastDoneActions extends StatelessWidget {
  /// The card's abstract, which holds the audio links.
  final String? abstractText;

  /// Plays an audio link; null plays through [podcastPlayFor].
  final PodcastPlay? onPlay;

  /// Creates the actions row for one card.
  const PodcastDoneActions( { super.key, required this.abstractText, this.onPlay } );

  @override
  Widget build( BuildContext context ) {
    final audio = parsePodcastAudio( abstractText );
    if ( audio.isEmpty ) return const SizedBox.shrink();

    final play  = onPlay ?? podcastPlayFor();
    return Wrap(
      spacing   : 8,
      runSpacing: 4,
      children  : [
        for ( var i = 0; i < audio.length; i++ )
          FilledButton.tonalIcon(
            key      : Key( "${TestKeys.podcastPlayPrefix}$i" ),
            onPressed: () => play( audio[ i ].url, audio[ i ].label ),
            icon     : const Icon( Icons.play_arrow ),
            label    : Text( audio.length == 1 ? "Play" : "Play ${audio[ i ].label}" ),
          ),
      ],
    );
  }
}
