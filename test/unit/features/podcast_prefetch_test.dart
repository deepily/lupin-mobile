import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/artifacts/podcast_prefetch.dart';
import 'package:lupin_mobile/services/audio/podcast_link.dart';
import '../../helpers/fake_podcast_cache.dart';

const String _done =
    "**English**: [▶️ Play Here](/app/audio?path=io%2Fa.mp3&embed=1)\n"
    "**Mexican Spanish**: [▶️ Play Here](/app/audio?path=io%2Fb.mp3&embed=1)\n";

void main() {
  late FakePodcastCache cache;
  late PodcastLink      link;
  late PodcastPrefetcher prefetcher;

  setUp( () {
    cache      = FakePodcastCache();
    link       = PodcastLink.unmetered;
    prefetcher = PodcastPrefetcher( cacheFactory: () => cache, linkProbe: () async => link );
  } );

  test( "on Wi-Fi it downloads every audio file the done card names", () async {
    expect( await prefetcher.prefetch( _done ), 2 );
    expect( cache.fetched, [ [ "io/a.mp3", "io%2Fa.mp3" ], [ "io/b.mp3", "io%2Fb.mp3" ] ] );
  } );

  test( "it skips files already on the phone", () async {
    cache.files[ "io%2Fa.mp3" ] = PathFile( "/kept/a.mp3" );
    expect( await prefetcher.prefetch( _done ), 1 );
    expect( cache.fetched.single.last, "io%2Fb.mp3" );
  } );

  test( "on mobile data or offline it downloads nothing", () async {
    for ( final l in [ PodcastLink.metered, PodcastLink.offline ] ) {
      link = l;
      expect( await prefetcher.prefetch( _done ), 0, reason: "$l" );
    }
    expect( cache.fetched, isEmpty );
  } );

  test( "a card with no audio, or no abstract, does nothing and does not even probe the link", () async {
    var probed = 0;
    prefetcher = PodcastPrefetcher( cacheFactory: () => cache, linkProbe: () async { probed++; return PodcastLink.unmetered; } );
    expect( await prefetcher.prefetch( null ), 0 );
    expect( await prefetcher.prefetch( "**Segments**: 4" ), 0 );
    expect( probed, 0 );
  } );

  test( "a failed download is skipped and the rest still download", () async {
    cache.failWith = StateError( "dropped" );
    expect( await prefetcher.prefetch( _done ), 0 );
    expect( cache.fetched.length, 2, reason: "the second file was still tried" );
  } );
}
