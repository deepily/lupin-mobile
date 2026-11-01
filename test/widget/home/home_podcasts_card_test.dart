import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/podcast_play.dart';
import 'package:lupin_mobile/features/home/home_screen.dart';
import 'package:lupin_mobile/features/podcasts/podcast_list_screen.dart';
import 'package:lupin_mobile/services/audio/podcast_catalog.dart';

import '../../helpers/fake_podcast_cache.dart';

void main() {
  final getIt = GetIt.instance;

  tearDown( () async => getIt.reset() );

  testWidgets( "the Podcasts card opens the list and shows a downloaded podcast", ( tester ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    final cache = FakePodcastCache();
    cache.files[ podcastCacheName( "io/a.mp3" ) ] = PathFile( "/x" );
    cache.savedTitles[ podcastCacheName( "io/a.mp3" ) ] = "Saved title";
    getIt.registerSingleton<PodcastCatalog>( PodcastCatalog( cache ) );

    await tester.pumpWidget( const MaterialApp( home: LupinHomeScreen() ) );
    await tester.pump();

    final card = find.byKey( const Key( TestKeys.homePodcastsCard ) );
    await tester.scrollUntilVisible( card, 120, scrollable: find.byType( Scrollable ).first );
    await tester.ensureVisible( card );
    await tester.pump();
    expect( find.text( "Podcasts" ), findsWidgets );
    await tester.tap( card );
    await tester.pumpAndSettle();

    expect( find.byType( PodcastListScreen ), findsOneWidget );
    expect( find.text( "Saved title" ), findsOneWidget );
  } );
}
