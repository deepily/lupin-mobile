import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/audio/mini_player_bar.dart';
import 'package:lupin_mobile/services/audio/podcast_link.dart';
import 'package:lupin_mobile/services/audio/podcast_player_service.dart';
import '../../helpers/fake_podcast_cache.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import '../../helpers/fake_podcast_engine.dart';

class _MockTts extends Mock implements TtsOrchestrator {}
class _F extends Fake implements File {
  @override
  String get path => "/tmp/a.mp3";
}

void main() {
  late FakeEngine           engine;
  late PodcastPlayerService svc;
  late FakePodcastCache     cache;

  setUp( () {
    cache  = FakePodcastCache();
    engine = FakeEngine();
    final tts = _MockTts();
    when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    svc = PodcastPlayerService( engineFactory: () => engine, cacheFactory: () => cache, linkProbe: () async => PodcastLink.unmetered, ttsFactory: () => tts );
  } );

  tearDown( () => svc.dispose() );

  Widget host() => MaterialApp( home: Scaffold( body: const Text( "screen" ), bottomNavigationBar: MiniPlayerBar( service: svc ) ) );

  testWidgets( "hidden while nothing is loaded", ( tester ) async {
    await tester.pumpWidget( host() );
    expect( find.byKey( const Key( TestKeys.miniPlayerToggle ) ), findsNothing );
  } );

  testWidgets( "shows a Downloaded marker only for a track kept on the phone", ( tester ) async {
    await tester.pumpWidget( host() );
    await svc.playFile( _F(), "Streamed", id: "pg-1" );
    await tester.pump();
    expect( find.byKey( const Key( TestKeys.miniPlayerDownloaded ) ), findsNothing );

    cache.files[ "pg-2" ] = _F();
    await svc.playFile( _F(), "Kept", id: "pg-2" );
    await tester.pump();
    expect( find.byKey( const Key( TestKeys.miniPlayerDownloaded ) ), findsOneWidget );
    expect( find.text( "Downloaded" ), findsOneWidget );
  } );

  testWidgets( "shows the title and progress, pauses and resumes", ( tester ) async {
    await tester.pumpWidget( host() );
    await svc.playFile( _F(), "My podcast", id: "pg-1" );
    engine.dur.add( const Duration( seconds: 100 ) );
    engine.pos.add( const Duration( seconds: 25 ) );
    await tester.pump();
    await tester.pump();

    expect( find.text( "My podcast" ), findsOneWidget );
    final bar = tester.widget<LinearProgressIndicator>( find.byType( LinearProgressIndicator ) );
    expect( bar.value, 0.25 );

    await tester.tap( find.byKey( const Key( TestKeys.miniPlayerToggle ) ) );
    await tester.pump();
    expect( svc.status, PodcastPlayerStatus.paused );
    expect( find.byIcon( Icons.play_arrow ), findsOneWidget );

    await tester.tap( find.byKey( const Key( TestKeys.miniPlayerToggle ) ) );
    await tester.pump();
    expect( svc.isPlaying, isTrue );
  } );

  testWidgets( "progress is zero until the duration is known", ( tester ) async {
    await tester.pumpWidget( host() );
    await svc.playFile( _F(), "T", id: "pg-1" );
    await tester.pump();
    expect( tester.widget<LinearProgressIndicator>( find.byType( LinearProgressIndicator ) ).value, 0.0 );
  } );

  testWidgets( "close stops playback and hides the bar", ( tester ) async {
    await tester.pumpWidget( host() );
    await svc.playFile( _F(), "T", id: "pg-1" );
    await tester.pump();
    await tester.tap( find.byKey( const Key( TestKeys.miniPlayerClose ) ) );
    await tester.pump();
    expect( svc.status, PodcastPlayerStatus.idle );
    expect( find.byKey( const Key( TestKeys.miniPlayerToggle ) ), findsNothing );
  } );

  testWidgets( "stays on screen across navigation because it lives above the Navigator", ( tester ) async {
    await tester.pumpWidget( MaterialApp(
      builder: ( c, child ) => Column( children: [ Expanded( child: child! ), MiniPlayerBar( service: svc ) ] ),
      home: Builder( builder: ( ctx ) => TextButton(
        onPressed: () => Navigator.of( ctx ).push( MaterialPageRoute<void>( builder: ( _ ) => const Scaffold( body: Text( "second" ) ) ) ),
        child: const Text( "go" ),
      ) ),
    ) );
    await svc.playFile( _F(), "T", id: "pg-1" );
    await tester.pump();
    await tester.tap( find.text( "go" ) );
    await tester.pumpAndSettle();
    expect( find.text( "second" ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.miniPlayerToggle ) ), findsOneWidget );
  } );

  testWidgets( "back button: tap backs up 15 seconds, long-press goes to the start", ( tester ) async {
    await tester.pumpWidget( host() );
    await svc.playFile( _F(), "My podcast", id: "pg-1" );
    engine.pos.add( const Duration( seconds: 100 ) );
    await tester.pump();
    engine.calls.clear();

    await tester.tap( find.byKey( const Key( TestKeys.miniPlayerBack ) ) );
    await tester.pump();
    expect( engine.calls, [ "seek:85" ] );
    expect( svc.isPlaying, isTrue );

    await tester.longPress( find.byKey( const Key( TestKeys.miniPlayerBack ) ) );
    await tester.pump();
    expect( engine.calls, [ "seek:85", "seek:0" ] );
  } );

  testWidgets( "back button is absent while nothing is loaded", ( tester ) async {
    await tester.pumpWidget( host() );
    expect( find.byKey( const Key( TestKeys.miniPlayerBack ) ), findsNothing );
  } );
}
