import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/artifacts/audio_artifact_player.dart';
import 'package:lupin_mobile/services/artifacts/io_file_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockController    extends Mock implements AudioPlaybackController {}
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
    late _MockController        ctrl;
    late _MockIoFileService     io;
    late _MockTtsOrchestrator   tts;
    late StreamController<Duration> posCtrl;
    late StreamController<Duration> durCtrl;
    late StreamController<void>     completeCtrl;

    setUp(() {
      ctrl         = _MockController();
      io           = _MockIoFileService();
      tts          = _MockTtsOrchestrator();
      posCtrl      = StreamController<Duration>.broadcast();
      durCtrl      = StreamController<Duration>.broadcast();
      completeCtrl = StreamController<void>.broadcast();

      when( () => ctrl.onPosition ).thenAnswer( ( _ ) => posCtrl.stream );
      when( () => ctrl.onDuration ).thenAnswer( ( _ ) => durCtrl.stream );
      when( () => ctrl.onComplete ).thenAnswer( ( _ ) => completeCtrl.stream );
      when( () => ctrl.play( any() ) ).thenAnswer( ( _ ) async {} );
      when( () => ctrl.pause()      ).thenAnswer( ( _ ) async {} );
      when( () => ctrl.resume()     ).thenAnswer( ( _ ) async {} );
      when( () => ctrl.stop()       ).thenAnswer( ( _ ) async {} );
      when( () => ctrl.dispose()    ).thenAnswer( ( _ ) async {} );

      when( () => tts.stopAll() ).thenAnswer( ( _ ) async {} );
    });

    tearDown(() async {
      await posCtrl.close();
      await durCtrl.close();
      await completeCtrl.close();
    });

    Widget underTest() {
      return MaterialApp(
        home: AudioArtifactPlayer(
          jobId           : "pg-12345",
          audioPath       : "/io/podcasts/u@x.y/pg-12345/podcast.mp3",
          controller      : ctrl,
          ioFileService   : io,
          ttsOrchestrator : tts,
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

    testWidgets( "tapping Play calls TtsOrchestrator.stopAll first then controller.play", ( tester ) async {
      when( () => io.downloadToCache( any(), any() ) )
          .thenAnswer( ( _ ) async => _FakeFile() );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPlayButton ) ) );
      await tester.pumpAndSettle();

      verifyInOrder( [
        () => tts.stopAll(),
        () => ctrl.play( any() ),
      ] );
      // Pause button is now visible (Play state).
      expect( find.byKey( const Key( TestKeys.audioPlayerPauseButton ) ), findsOneWidget );
    });

    testWidgets( "Pause then Play resumes (calls resume not play)", ( tester ) async {
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

      verify( () => ctrl.pause() ).called( 1 );

      // Play again — should hit resume(), NOT play().
      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerPlayButton ) ) );
      await tester.pumpAndSettle();

      verify( () => ctrl.resume() ).called( 1 );
      // play() was only called ONCE (from the first tap, not the resume).
      verify( () => ctrl.play( any() ) ).called( 1 );
    });

    testWidgets( "tapping Stop calls controller.stop and resets position", ( tester ) async {
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

      verify( () => ctrl.stop() ).called( greaterThanOrEqualTo( 1 ) );
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
          controller      : ctrl,
          ioFileService   : io,
          ttsOrchestrator : tts,
        ),
      );

      await tester.pumpWidget( emptyPathWidget() );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.audioPlayerDownloadButton ) ) );
      await tester.pump();

      verifyNever( () => io.downloadToCache( any(), any() ) );
      expect( find.textContaining( "No audio path" ), findsOneWidget );
    });
  });
}
