import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/audio_artifact_player.dart';
import 'package:lupin_mobile/services/artifacts/io_file_service.dart';
import 'package:lupin_mobile/services/audio/podcast_link.dart';
import 'package:lupin_mobile/services/audio/podcast_player_service.dart';
import '../../helpers/fake_podcast_cache.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import '../../helpers/fake_podcast_engine.dart';

class _MockIoFileService extends Mock implements IoFileService {}
class _MockTtsOrchestrator extends Mock implements TtsOrchestrator {}
class _FakeFile          extends Fake implements File {
  @override
  String get path => "/tmp/job-1.mp3";
}

void main() {
  setUpAll(() {
    registerFallbackValue( _FakeFile() );
  });

  group( "AudioArtifactPlayer", () {
    late FakeEngine             engine;
    late _MockIoFileService     io;
    late _MockTtsOrchestrator   tts;
    late PodcastPlayerService   svc;

    setUp(() {
      engine = FakeEngine();
      io     = _MockIoFileService();
      tts    = _MockTtsOrchestrator();
      svc    = PodcastPlayerService(
        engineFactory : () => engine,
        cacheFactory  : FakePodcastCache.new,
        linkProbe     : () async => PodcastLink.unmetered,
        ttsFactory    : () => tts,
      );
      when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    });

    tearDown( () => svc.dispose() );

    Widget underTest() {
      return MaterialApp(
        home: AudioArtifactPlayer(
          jobId           : "pg-12345",
          audioPath       : "/io/podcasts/u@x.y/pg-12345/podcast.mp3",
          playerService   : svc,
          ioFileService   : io,
        ),
      );
    }

    testWidgets( "initial state shows Download button only (no transport)", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.audioPlayerPlayButton     ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.audioPlayerSlider         ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.audioPlayerShareButton    ) ), findsNothing );
    });

    testWidgets( "tapping Download fetches via IoFileService and reveals transport controls", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) )
          .thenAnswer( ( _ ) async => _FakeFile() );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();

      verify( () => io.downloadToCache( "/io/podcasts/u@x.y/pg-12345/podcast.mp3", "pg-12345.mp3" ) ).called( 1 );
      expect( find.byKey( const Key( TestKeys.audioPlayerPlayButton  ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.audioPlayerStopButton  ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.audioPlayerSlider      ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.audioPlayerShareButton ) ), findsOneWidget );
    });

    testWidgets( "tapping Play stops TTS then loads and plays on the app-wide service", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) )
          .thenAnswer( ( _ ) async => _FakeFile() );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPlayButton ) ) );
      await tester.pumpAndSettle();

      verify( () => tts.stopAll() ).called( 1 );
      expect( engine.calls, [ "load:pg-12345:pg-12345:/tmp/job-1.mp3", "play" ] );
      // Pause button is now visible (Play state).
      expect( find.byKey( const Key( TestKeys.audioPlayerPauseButton ) ), findsOneWidget );
    });

    testWidgets( "Pause then Play resumes without reloading", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) )
          .thenAnswer( ( _ ) async => _FakeFile() );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPlayButton ) ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPauseButton ) ) );
      await tester.pumpAndSettle();

      expect( engine.calls, contains( "pause" ) );

      // Play again — should hit resume(), NOT play().
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPlayButton ) ) );
      await tester.pumpAndSettle();

      expect( engine.calls.where( ( c ) => c.startsWith( "load" ) ).length, 1 );
      expect( engine.calls.where( ( c ) => c == "play" ).length, 2 );
    });

    testWidgets( "tapping Stop stops the service and returns to the Play state", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) )
          .thenAnswer( ( _ ) async => _FakeFile() );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPlayButton ) ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerStopButton ) ) );
      await tester.pumpAndSettle();

      expect( engine.calls, contains( "stop" ) );
      // Back to Play state (Pause button gone).
      expect( find.byKey( const Key( TestKeys.audioPlayerPauseButton ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.audioPlayerPlayButton  ) ), findsOneWidget );
    });

    testWidgets( "tapping Share calls IoFileService.shareToExternalApp with the cached file", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) )
          .thenAnswer( ( _ ) async => _FakeFile() );
      when( () => io.shareToExternalApp( any() ) )
          .thenAnswer( ( _ ) async {} );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerShareButton ) ) );
      await tester.pumpAndSettle();

      verify( () => io.shareToExternalApp( any() ) ).called( 1 );
    });

    testWidgets( "empty audioPath shows error state without calling IoFileService", ( tester ) async {
      Widget emptyPathWidget() => MaterialApp(
        home: AudioArtifactPlayer(
          jobId           : "pg-12345",
          audioPath       : "",
          playerService   : svc,
          ioFileService   : io,
        ),
      );

      await tester.pumpWidget( emptyPathWidget() );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pump();

      verifyNever( () => io.downloadToCache( any(), any() ) );
      expect( find.textContaining( "No audio path" ), findsOneWidget );
    });

    testWidgets( "audio keeps playing after the screen is popped, and reopening shows the live track", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) ).thenAnswer( ( _ ) async => _FakeFile() );

      await tester.pumpWidget( MaterialApp(
        home: Builder( builder: ( ctx ) => TextButton(
          onPressed: () => Navigator.of( ctx ).push( MaterialPageRoute<void>(
            builder: ( _ ) => AudioArtifactPlayer(
              jobId: "pg-12345", audioPath: "/io/p.mp3", playerService: svc, ioFileService: io ),
          ) ),
          child: const Text( "open" ),
        ) ),
      ) );
      await tester.tap( find.text( "open" ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPlayButton ) ) );
      await tester.pumpAndSettle();

      // Pop the screen: the audio must not stop.
      Navigator.of( tester.element( find.byType( AudioArtifactPlayer ) ) ).pop();
      await tester.pumpAndSettle();
      expect( find.byType( AudioArtifactPlayer ), findsNothing );
      expect( svc.isPlaying, isTrue );
      expect( engine.calls, isNot( contains( "stop" ) ) );

      // Reopen: transport shows at once, in the playing state, with no second download.
      await tester.tap( find.text( "open" ) );
      await tester.pumpAndSettle();
      expect( find.byKey( const Key( TestKeys.audioPlayerPauseButton ) ), findsOneWidget );
      verify( () => io.downloadToCache( any(), any() ) ).called( 1 );
    });

    testWidgets( "Stop on a screen whose track is not the loaded one leaves the other track playing", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) ).thenAnswer( ( _ ) async => _FakeFile() );
      await svc.playFile( _FakeFile(), "other", id: "pg-other" );
      await tester.pumpWidget( underTest() );
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerStopButton ) ) );
      await tester.pumpAndSettle();
      expect( svc.trackId, "pg-other" );
    });
  });
}
