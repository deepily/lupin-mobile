/// Row 9b1f7701 — debug "Keep voice recordings": when ON, every recording is
/// copied to the kept-recordings folder before `discardPendingUpload` deletes
/// it; when OFF nothing is copied; a failed copy never stops the delete.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';

import '../../quick_ask/_quick_ask_harness.dart';

class _MockDio      extends Mock implements Dio {}
class _MockRecorder extends Mock implements AudioRecorder {}

const _wavBytes = [ 0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45 ];

void main() {
  late _MockRecorder recorder;
  late Directory     tempDir;
  late Directory     keptDir;
  late bool          keepOn;
  late int           copies;
  late bool          copyThrows;

  setUpAll( () {
    registerFallbackValue( const RecordConfig() );
    registerFallbackValue( const AskRequest( question: '_fallback' ) );
  } );

  setUp( () async {
    recorder   = _MockRecorder();
    tempDir    = await Directory.systemTemp.createTemp( 'asr-keep-tmp-' );
    final root = await Directory.systemTemp.createTemp( 'asr-keep-ext-' );
    keptDir    = Directory( '${root.path}/recordings' );
    keepOn     = false;
    copies     = 0;
    copyThrows = false;

    when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
    when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( _ ) async {} );
    when( () => recorder.cancel() ).thenAnswer( ( _ ) async {} );
  } );

  tearDown( () async {
    if ( tempDir.existsSync() ) await tempDir.delete( recursive: true );
    if ( keptDir.parent.existsSync() ) await keptDir.parent.delete( recursive: true );
  } );

  AsrService build() => AsrService(
    dio             : _MockDio(),
    recorder        : recorder,
    tempDirProvider : () async => tempDir,
    keepRecordings  : () => keepOn,
    keptDirProvider : () async => keptDir,
    clock           : () => DateTime( 2026, 9, 15, 7, 8, 9 ),
    copyFile        : ( src, dest ) async {
      copies++;
      if ( copyThrows ) throw const FileSystemException( 'disk full' );
      await src.copy( dest );
    },
  );

  /// Record, have the mock recorder "write" the WAV, stop to file.
  Future<String> recordToFile( AsrService asr ) async {
    await asr.startRecording();
    final path = verify( () => recorder.start( any(), path: captureAny( named: 'path' ) ) )
        .captured.single as String;
    File( path ).writeAsBytesSync( _wavBytes );
    when( () => recorder.stop() ).thenAnswer( ( _ ) async => path );
    return asr.stopToFile();
  }

  group( 'AsrService keep voice recordings', () {
    test( 'OFF → no copy, the file is deleted synchronously', () async {
      final asr  = build();
      final path = await recordToFile( asr );

      asr.discardPendingUpload( path );

      expect( File( path ).existsSync(), isFalse, reason: 'OFF deletes before returning, as before' );
      expect( copies, 0 );
      expect( asr.lastKeep, isNull );
      expect( keptDir.existsSync(), isFalse, reason: 'OFF touches no folder' );
    } );

    test( 'ON → copy with the same bytes, named rec-<stamp>-<n>.wav, then the original is deleted', () async {
      keepOn     = true;
      final asr  = build();
      final path = await recordToFile( asr );

      asr.discardPendingUpload( path );
      await asr.lastKeep;

      expect( File( path ).existsSync(), isFalse );
      final kept = File( '${keptDir.path}/rec-20260915-070809-1.wav' );
      expect( kept.existsSync(), isTrue );
      expect( kept.readAsBytesSync(), _wavBytes );

      // A second recording gets the next number.
      final second = await recordToFile( asr );
      asr.discardPendingUpload( second );
      await asr.lastKeep;
      expect( File( '${keptDir.path}/rec-20260915-070809-2.wav' ).existsSync(), isTrue );
      expect( File( second ).existsSync(), isFalse );
    } );

    test( 'ON + copy throws → the original is still deleted and nothing escapes', () async {
      keepOn     = true;
      copyThrows = true;
      final asr  = build();
      final path = await recordToFile( asr );

      expect( () => asr.discardPendingUpload( path ), returnsNormally );
      await expectLater( asr.lastKeep, completes );

      expect( copies, 1 );
      expect( File( path ).existsSync(), isFalse );
    } );

    test( 'ON + folder cannot be resolved → the original is still deleted', () async {
      keepOn    = true;
      final asr = AsrService(
        dio             : _MockDio(),
        recorder        : recorder,
        tempDirProvider : () async => tempDir,
        keepRecordings  : () => true,
        keptDirProvider : () async => throw StateError( 'no external storage' ),
      );
      final path = await recordToFile( asr );

      asr.discardPendingUpload( path );
      await expectLater( asr.lastKeep, completes );
      expect( File( path ).existsSync(), isFalse );
    } );

    test( 'a path the service never handed out is neither copied nor deleted', () async {
      keepOn       = true;
      final asr    = build();
      final stray  = File( '${tempDir.path}/stranger.wav' )..writeAsBytesSync( _wavBytes );

      asr.discardPendingUpload( stray.path );

      expect( asr.lastKeep, isNull );
      expect( copies, 0 );
      expect( stray.existsSync(), isTrue );
    } );
  } );

  group( 'Quick Ask send-immediately also keeps when ON', () {
    test( "the bloc's spoken-ask ending keeps the recording, then deletes it", () async {
      keepOn   = true;
      final asr = build();

      final repo          = MockQueueRepository();
      final ws            = MockWebSocketService();
      final notifications = MockNotificationRepository();
      final ctrl          = StreamController<SpokenAskEvent>();
      String? askedPath;

      when( () => ws.sessionId ).thenReturn( ourSession );
      when( () => ws.connectionStream ).thenAnswer( ( _ ) async* { yield true; } );
      String? startedPath;
      when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( inv ) async {
        startedPath = inv.namedArguments[ #path ] as String;
        File( startedPath! ).writeAsBytesSync( _wavBytes );
      } );
      when( () => recorder.stop() ).thenAnswer( ( _ ) async => startedPath );
      when( () => repo.askSpoken( any(), any() ) ).thenAnswer( ( inv ) {
        askedPath = inv.positionalArguments.first as String;
        return ctrl.stream;
      } );

      final bloc = QuickAskBloc(
        repo,
        asr                  : asr,
        ws                   : ws,
        notifications        : notifications,
        prefs                : FakeQuickAskPreferences( stored: true ),
        userEmail            : ourEmail,
        requestMicPermission : () async => true,
      );

      await settle();   // let the CONNECTED replay land first
      bloc.add( const QuickAskRecordPressed() );
      await settle();
      bloc.add( const QuickAskRecordReleased() );
      await settle();
      expect( askedPath, isNotNull, reason: 'send-immediately posted the recording; state: ${bloc.state}' );
      expect( File( askedPath! ).existsSync(), isTrue );

      ctrl.add( const SpokenAskFailed( 'No speech was recognised, so nothing was asked.', statusCode: 422 ) );
      await settle();
      await asr.lastKeep;

      expect( File( askedPath! ).existsSync(), isFalse );
      final kept = File( '${keptDir.path}/rec-20260915-070809-1.wav' );
      expect( kept.existsSync(), isTrue );
      expect( kept.readAsBytesSync(), _wavBytes );

      await bloc.close();
      await ctrl.close();
    } );
  } );

  test( 'keptFileNameFor pads every field', () {
    expect( AsrService.keptFileNameFor( DateTime( 2026, 1, 2, 3, 4, 5 ), 7 ), 'rec-20260102-030405-7.wav' );
  } );
}
