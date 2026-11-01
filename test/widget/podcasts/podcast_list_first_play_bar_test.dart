import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/audio/mini_player_bar.dart';
import 'package:lupin_mobile/features/podcasts/podcast_list_screen.dart';
import 'package:lupin_mobile/services/audio/podcast_catalog.dart';
import 'package:lupin_mobile/services/audio/podcast_link.dart';
import 'package:lupin_mobile/services/audio/podcast_player_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

import '../../helpers/fake_podcast_cache.dart';
import '../../helpers/fake_podcast_engine.dart';

class _MockTts extends Mock implements TtsOrchestrator {}

/// Bug: the first Play on the Podcasts list left the mini-player bar hidden.
///
/// The platform engine's play() stays pending until the track ends, so the service must not wait on it.
void main() {
  testWidgets( "one Play from the Podcasts list shows the bar at once, with an engine whose play() stays pending", ( t ) async {
    final engine  = FakeEngine()..playEnds = Completer<void>();
    final cache   = FakePodcastCache();
    final tts     = _MockTts();
    when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    final svc     = PodcastPlayerService( engineFactory: () => engine, cacheFactory: () => cache, linkProbe: () async => PodcastLink.unmetered, ttsFactory: () => tts );
    final catalog = PodcastCatalog( cache );
    catalog.record( "**Podcast**: [x](/app/audio?path=io/new.mp3)", title: "New one", at: DateTime( 2026, 10, 31 ) );

    // The bar sits above the Navigator, as in app.dart; the list is a pushed route.
    await t.pumpWidget( MaterialApp(
      builder: ( context, child ) => Column( children: [ Expanded( child: child! ), MiniPlayerBar( service: svc ) ] ),
      home   : Builder( builder: ( ctx ) => Scaffold( body: TextButton(
        onPressed: () => Navigator.of( ctx ).push( MaterialPageRoute<void>( builder: ( _ ) => PodcastListScreen( catalog: catalog, onPlay: podcastPlayFor( service: svc ) ) ) ),
        child    : const Text( "open" ),
      ) ) ),
    ) );
    await t.tap( find.text( "open" ) );
    await t.pumpAndSettle();
    expect( find.byKey( const Key( TestKeys.miniPlayerToggle ) ), findsNothing );

    await t.tap( find.byKey( Key( "${TestKeys.podcastListPlayPrefix}${podcastCacheName( "io/new.mp3" )}" ) ) );
    await t.pumpAndSettle();

    expect( svc.isPlaying, isTrue );
    expect( find.byKey( const Key( TestKeys.miniPlayerToggle ) ), findsOneWidget );
    svc.dispose();
  } );
}
