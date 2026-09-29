import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/voice_reply_field.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockAsr      extends Mock implements AsrService {}
class _MockRecorder extends Mock implements AudioRecorder {}
class _MockDio      extends Mock implements Dio {}
class _MockPlayer   extends Mock implements StreamingTtsPlayer {}
class _MockFallback extends Mock implements NotificationAudioService {}
class _MockWs       extends Mock implements WebSocketService {}

void main() {
  group( 'VoiceReplyField (S4)', () {
    late _MockAsr     asr;
    late List<String> submitted;

    setUp( () {
      asr       = _MockAsr();
      submitted = [];
      when( () => asr.startRecording()   ).thenAnswer( ( _ ) async {} );
      when( () => asr.cancelRecording()  ).thenAnswer( ( _ ) async {} );
    } );

    Widget host( { Future<bool> Function()? permission } ) {
      return MaterialApp(
        home: Scaffold(
          body: VoiceReplyField(
            asr                  : asr,
            onSubmit             : submitted.add,
            requestMicPermission : permission ?? () async => true,
          ),
        ),
      );
    }

    Finder byKeyStr( String k ) => find.byKey( Key( k ) );

    testWidgets( 'AC-S4.4 — full state machine; Send fires onSubmit EXACTLY ONCE with the edited text and resets to idle', ( tester ) async {
      when( () => asr.stopAndTranscribe() )
          .thenAnswer( ( _ ) async => 'hello from whisper' );

      await tester.pumpWidget( host() );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget );   // idle

      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );          // → recording
      await tester.pump();
      expect( find.textContaining( 'Recording…' ), findsOneWidget );

      await tester.pump( const Duration( seconds: 2 ) );               // elapsed ticks
      expect( find.textContaining( '2s' ), findsOneWidget );

      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );          // → transcribing → review
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      final field = byKeyStr( TestKeys.voiceReplyTranscript );
      expect( field, findsOneWidget );                                 // review
      expect( find.text( 'hello from whisper' ), findsOneWidget );

      await tester.enterText( field, 'hello from whisper, edited' );   // transcript is a seed, not a cage
      await tester.tap( byKeyStr( TestKeys.voiceReplySend ) );
      await tester.pump();

      expect( submitted, [ 'hello from whisper, edited' ],
          reason: 'onSubmit exactly once, edited text, no repository call from the widget' );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget,
          reason: 'reset to idle after send' );
      expect( byKeyStr( TestKeys.voiceReplyTranscript ), findsNothing );
    } );

    testWidgets( 'AC-S4.5 — mic-permission denied renders inline guidance, no exception, stays idle', ( tester ) async {
      await tester.pumpWidget( host( permission: () async => false ) );

      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );
      await tester.pump();

      expect( byKeyStr( TestKeys.voiceReplyError ), findsOneWidget );
      expect( find.textContaining( 'permission' ), findsOneWidget );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget, reason: 'still idle' );
      verifyNever( () => asr.startRecording() );
      expect( submitted, isEmpty );
    } );

    testWidgets( 'AC-S4.8 — transcribe failure renders the error affordance and returns to idle; no stuck spinner, no onSubmit', ( tester ) async {
      when( () => asr.stopAndTranscribe() )
          .thenThrow( const AsrException( 'Transcription upload failed: timeout' ) );

      await tester.pumpWidget( host() );
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );   // → recording
      await tester.pump();
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );   // → transcribing → throws
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      expect( byKeyStr( TestKeys.voiceReplyError ), findsOneWidget );
      expect( find.textContaining( 'upload failed' ), findsOneWidget );
      expect( find.byType( CircularProgressIndicator ), findsNothing,
          reason: 'never a vanishing/stuck spinner (F-S4-S2-1a)' );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget, reason: 'back to idle' );
      expect( submitted, isEmpty );

      // Dismiss affordance clears the message.
      await tester.tap( find.descendant(
        of       : byKeyStr( TestKeys.voiceReplyError ),
        matching : find.byIcon( Icons.close ),
      ) );
      await tester.pump();
      expect( byKeyStr( TestKeys.voiceReplyError ), findsNothing );
    } );

    testWidgets( 'AC-S4.8 — cancel during transcribing discards the in-flight result; idle, no onSubmit', ( tester ) async {
      final gate = Completer<String>();
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );

      await tester.pumpWidget( host() );
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );   // → recording
      await tester.pump();
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );   // → transcribing (parked)
      await tester.pump();
      expect( find.byType( CircularProgressIndicator ), findsOneWidget );

      await tester.tap( byKeyStr( TestKeys.voiceReplyCancel ) );
      await tester.pump();
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget, reason: 'immediately idle' );

      gate.complete( 'late transcript' );                       // in-flight completes AFTER cancel
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      expect( byKeyStr( TestKeys.voiceReplyTranscript ), findsNothing,
          reason: 'stale result dropped — no resurrected review state' );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget );
      expect( submitted, isEmpty );
    } );

    testWidgets( 'cancel during recording discards via AsrService and returns to idle', ( tester ) async {
      await tester.pumpWidget( host() );
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );   // → recording
      await tester.pump();

      await tester.tap( byKeyStr( TestKeys.voiceReplyCancel ) );
      await tester.pump();

      verify( () => asr.cancelRecording() ).called( 1 );
      verifyNever( () => asr.stopAndTranscribe() );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget );
    } );

    // Row 0b40272e — what Rick called truncation. Both halves: a capture that
    // heard nothing used to open an EMPTY review box with a live Send button,
    // and the transcript shared one row with two buttons at four lines.
    testWidgets( 'a capture that heard nothing says so and stays idle — no empty review box', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => '   ' );

      await tester.pumpWidget( host() );
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );
      await tester.pump();
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      expect( byKeyStr( TestKeys.voiceReplyTranscript ), findsNothing,
          reason: 'nothing was heard, so there is nothing to review or send' );
      expect( byKeyStr( TestKeys.voiceReplyError ), findsOneWidget );
      expect( find.textContaining( 'Did not catch anything' ), findsOneWidget );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget, reason: 'still idle' );
      expect( submitted, isEmpty );
    } );

    testWidgets( 'the review transcript gets the FULL width, with the buttons below it', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async =>
          'a reply long enough that a four-line box beside two icon buttons would cut it off '
          'well before the end of what was actually said out loud' );

      await tester.pumpWidget( host() );
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );
      await tester.pump();
      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      final field = tester.getRect( byKeyStr( TestKeys.voiceReplyTranscript ) );
      final pane  = tester.getRect( find.byType( VoiceReplyField ) );
      expect( field.width, pane.width,
          reason: 'THE BUG: the transcript used to share its row with Send and Discard' );

      final send = tester.getRect( byKeyStr( TestKeys.voiceReplySend ) );
      expect( send.top, greaterThanOrEqualTo( field.bottom ),
          reason: 'buttons below the text, not beside it' );
      expect( tester.widget<TextField>( byKeyStr( TestKeys.voiceReplyTranscript ) ).maxLines, 8 );
    } );

    // Rick 2026-09-17: the composer was too thin for a thumb — 25% taller.
    testWidgets( 'the mic row and its buttons are 25% taller than a stock 48 dp row', ( tester ) async {
      await tester.pumpWidget( host() );
      expect( kVoiceReplyRowHeight, 48.0 * 1.25 );

      final mic = tester.getSize( byKeyStr( TestKeys.voiceReplyMic ) );
      expect( mic.height, greaterThanOrEqualTo( kVoiceReplyRowHeight ), reason: 'idle mic tap target' );
      expect( mic.width,  greaterThanOrEqualTo( kVoiceReplyRowHeight ) );
      expect( tester.getSize( find.byType( VoiceReplyField ) ).height,
          greaterThanOrEqualTo( kVoiceReplyRowHeight ) );

      await tester.tap( byKeyStr( TestKeys.voiceReplyMic ) );   // → recording
      await tester.pump();
      expect( tester.getSize( byKeyStr( TestKeys.voiceReplyMic ) ).height,
          greaterThanOrEqualTo( kVoiceReplyRowHeight ), reason: 'stop button' );
      expect( tester.getSize( byKeyStr( TestKeys.voiceReplyCancel ) ).height,
          greaterThanOrEqualTo( kVoiceReplyRowHeight ), reason: 'discard button' );
    } );

    // Review LOW (2026-09-27): the edit button opens the review box with
    // nothing ever recorded, so discarding it must not reach the recorder.
    testWidgets( 'discarding an edit-opened review box does NOT cancel a recorder that never ran', ( tester ) async {
      await tester.pumpWidget( host() );

      await tester.tap( byKeyStr( TestKeys.voiceReplyEdit ) );    // → review, no recording
      await tester.pump();
      expect( byKeyStr( TestKeys.voiceReplyTranscript ), findsOneWidget );

      await tester.tap( byKeyStr( TestKeys.voiceReplyCancel ) );
      await tester.pump();

      verifyNever( () => asr.cancelRecording() );
      verifyNever( () => asr.startRecording() );
      expect( byKeyStr( TestKeys.voiceReplyMic ), findsOneWidget, reason: 'back to idle' );
      expect( submitted, isEmpty );
    } );
  } );

  /// Row 570c2fce (Rick, P0): "it needs to actually be able to record new
  /// chunks and append them to the end of what's already in the editor box."
  ///
  /// The editor box had no microphone once it was open, so a second thought had
  /// to be TYPED. These pin the append: the words land at the caret, what was
  /// there already survives every outcome — refusal, cancel, error, silence —
  /// and nothing ever replaces the box's contents.
  group( 'VoiceReplyField append mic (row 570c2fce)', () {
    late _MockAsr     asr;
    late List<String> submitted;

    setUp( () {
      asr       = _MockAsr();
      submitted = [];
      when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
      when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
    } );

    Widget host( { Future<bool> Function()? permission } ) => MaterialApp(
      home: Scaffold(
        body: VoiceReplyField(
          asr                  : asr,
          onSubmit             : submitted.add,
          requestMicPermission : permission ?? () async => true,
        ),
      ),
    );

    Finder byKeyStr( String k ) => find.byKey( Key( k ) );

    TextEditingController boxOf( WidgetTester tester ) =>
        tester.widget<TextField>( byKeyStr( TestKeys.voiceReplyTranscript ) ).controller!;

    /// Opens the review box holding [text]: the edit button, then typing, so the
    /// starting state is the operator's own text and not a transcript.
    Future<void> openWith( WidgetTester tester, String text ) async {
      await tester.pumpWidget( host() );
      await tester.tap( byKeyStr( TestKeys.voiceReplyEdit ) );
      await tester.pump();
      if ( text.isNotEmpty ) {
        await tester.enterText( byKeyStr( TestKeys.voiceReplyTranscript ), text );
        await tester.pump();
      }
    }

    /// One full append: tap the mic, tap it again to stop and transcribe.
    Future<void> dictate( WidgetTester tester ) async {
      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );
      await tester.pump();
      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );
    }

    testWidgets( 'APPENDS to what the box already holds — the existing text is never replaced', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'and one more thing' );

      await openWith( tester, 'what I typed first' );
      await dictate( tester );

      expect( boxOf( tester ).text, 'what I typed first and one more thing' );
      expect( byKeyStr( TestKeys.voiceReplyTranscript ), findsOneWidget,
          reason: 'still in the editor box, ready to send or dictate again' );
      expect( submitted, isEmpty, reason: 'an append is not a send' );
    } );

    testWidgets( 'a SECOND chunk appends after the first — new chunks, plural', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'chunk' );

      await openWith( tester, 'seed' );
      await dictate( tester );
      await dictate( tester );

      expect( boxOf( tester ).text, 'seed chunk chunk' );
    } );

    testWidgets( 'into an EMPTY box the transcript stands alone, with no leading space', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'the only words' );

      await openWith( tester, '' );
      await dictate( tester );

      expect( boxOf( tester ).text, 'the only words' );
    } );

    testWidgets( 'the caret ends up after the words just added, so the next chunk continues there', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'spoken' );

      await openWith( tester, 'typed' );
      await dictate( tester );

      final box = boxOf( tester );
      expect( box.text, 'typed spoken' );
      expect( box.selection, const TextSelection.collapsed( offset: 12 ) );
    } );

    testWidgets( 'the words land at the caret the box held when recording began, not blindly at the end', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'middle' );

      await openWith( tester, 'head tail' );
      // Caret between 'head ' and 'tail', then recording begins.
      boxOf( tester ).selection = const TextSelection.collapsed( offset: 5 );
      await tester.pump();
      await dictate( tester );

      final box = boxOf( tester );
      expect( box.text, 'head middle tail' );
      expect( box.selection, const TextSelection.collapsed( offset: 11 ) );
    } );

    testWidgets( 'PERMISSION DENIED: inline guidance, the box and its text untouched, recorder never started', ( tester ) async {
      await tester.pumpWidget( host( permission: () async => false ) );
      await tester.tap( byKeyStr( TestKeys.voiceReplyEdit ) );
      await tester.pump();
      await tester.enterText( byKeyStr( TestKeys.voiceReplyTranscript ), 'my draft' );
      await tester.pump();

      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );
      await tester.pump();

      expect( byKeyStr( TestKeys.voiceReplyError ), findsOneWidget );
      expect( find.textContaining( 'permission' ), findsOneWidget );
      expect( boxOf( tester ).text, 'my draft', reason: 'a refusal must not cost the draft' );
      expect( byKeyStr( TestKeys.voiceReplyAppendMic ), findsOneWidget, reason: 'mic back to idle' );
      verifyNever( () => asr.startRecording() );
    } );

    testWidgets( 'CANCELLED: discarding the recording leaves the text exactly as it was, and never transcribes', ( tester ) async {
      await openWith( tester, 'keep me' );

      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );      // recording
      await tester.pump();
      expect( find.textContaining( 'Recording…' ), findsOneWidget );
      expect( byKeyStr( TestKeys.voiceReplySend ), findsNothing,
          reason: 'no send button to fat-finger while a chunk is being recorded' );

      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendCancel ) );
      await tester.pump();

      verify( () => asr.cancelRecording() ).called( 1 );
      verifyNever( () => asr.stopAndTranscribe() );
      expect( boxOf( tester ).text, 'keep me' );
      expect( byKeyStr( TestKeys.voiceReplySend ), findsOneWidget, reason: 'back to the editor box' );
    } );

    testWidgets( 'a cancel that overtakes an in-flight transcribe drops the words and frees the mic', ( tester ) async {
      final gate = Completer<String>();
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );

      await openWith( tester, 'draft' );
      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );      // recording
      await tester.pump();
      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );      // transcribing, parked
      await tester.pump();
      expect( find.byType( CircularProgressIndicator ), findsOneWidget );

      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendCancel ) );
      await tester.pump();

      gate.complete( 'too late' );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      expect( boxOf( tester ).text, 'draft', reason: 'a stale transcript appends nothing' );
      expect( find.byType( CircularProgressIndicator ), findsNothing, reason: 'the mic is free again' );
      expect( byKeyStr( TestKeys.voiceReplyAppendMic ), findsOneWidget );
    } );

    testWidgets( 'ASR ERROR leaves the text untouched and says what went wrong', ( tester ) async {
      when( () => asr.stopAndTranscribe() )
          .thenThrow( const AsrException( 'Transcription upload failed: timeout' ) );

      await openWith( tester, 'half a sentence' );
      await dictate( tester );

      expect( boxOf( tester ).text, 'half a sentence' );
      expect( byKeyStr( TestKeys.voiceReplyError ), findsOneWidget );
      expect( find.textContaining( 'upload failed' ), findsOneWidget );
      expect( find.byType( CircularProgressIndicator ), findsNothing, reason: 'no stuck spinner' );
      expect( byKeyStr( TestKeys.voiceReplyAppendMic ), findsOneWidget );
      expect( submitted, isEmpty );
    } );

    testWidgets( 'NEGATIVE CONTROL — a capture that heard nothing appends nothing and says so', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => '   ' );

      await openWith( tester, 'untouched' );
      await dictate( tester );

      expect( boxOf( tester ).text, 'untouched',
          reason: 'silence must not append, and must not blank the box either' );
      expect( find.textContaining( 'Did not catch anything' ), findsOneWidget );
      expect( byKeyStr( TestKeys.voiceReplyAppendMic ), findsOneWidget );
    } );

    testWidgets( 'the append mic belongs to the OPEN editor box — the idle row keeps its own two buttons', ( tester ) async {
      await tester.pumpWidget( host() );
      expect( byKeyStr( TestKeys.voiceReplyAppendMic ), findsNothing, reason: 'nothing to append to yet' );

      await tester.tap( byKeyStr( TestKeys.voiceReplyEdit ) );
      await tester.pump();
      expect( byKeyStr( TestKeys.voiceReplyAppendMic ), findsOneWidget );
      expect( tester.getSize( byKeyStr( TestKeys.voiceReplyAppendMic ) ).height,
          greaterThanOrEqualTo( kVoiceReplyRowHeight ), reason: "Rick's thumb — same 60 dp target" );
    } );

    // Tiffany's guard (2026-09-28): an append must never OVERWRITE what was
    // edited while the chunk was recording. The caret is read at the start of
    // the recording but the text is read when the words arrive, so a draft
    // rewritten mid-recording keeps every character of the rewrite.
    testWidgets( 'text typed WHILE the chunk records survives the append — nothing is overwritten', ( tester ) async {
      final gate = Completer<String>();
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );

      await openWith( tester, 'first' );
      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );      // recording
      await tester.pump();

      // He keeps typing while he talks; the box is live throughout.
      await tester.enterText( byKeyStr( TestKeys.voiceReplyTranscript ), 'first, then typed more' );
      await tester.pump();

      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );      // stop → transcribing
      await tester.pump();
      gate.complete( 'and spoken' );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      expect( boxOf( tester ).text, 'first, then typed more and spoken',
          reason: 'every typed character survives, and the words land after them' );
    } );
    testWidgets( 'leaving the screen mid-append cancels the recording rather than abandoning it', ( tester ) async {
      await openWith( tester, 'draft' );
      await tester.tap( byKeyStr( TestKeys.voiceReplyAppendMic ) );
      await tester.pump();

      await tester.pumpWidget( const MaterialApp( home: Scaffold( body: SizedBox() ) ) );
      await tester.pump();

      verify( () => asr.cancelRecording() ).called( 1 );
    } );
  } );

  /// Review FAIL (2026-09-27), row a1c12c6e: the hold is only as good as its
  /// release. Navigating away mid-recording used to abandon the capture, and
  /// because `AsrService` is a singleton the hold outlived the widget — TTS
  /// went silent for the rest of the app session, with no indicator and no
  /// recovery. Wired end to end here (real service, real orchestrator) so the
  /// test fails if EITHER half of the release chain breaks.
  group( 'VoiceReplyField disposal releases the capture hold', () {
    late _MockRecorder    recorder;
    late AsrService       asr;
    late TtsOrchestrator  orch;
    late StreamController<TtsCompleteEvent> completeCtrl;
    late StreamController<TtsErrorEvent>    errorCtrl;

    setUpAll( () {
      registerFallbackValue( const RecordConfig() );
      registerFallbackValue( AudioEncoder.wav );
    } );

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      final prefs    = NotificationPreferences( await SharedPreferences.getInstance() );
      final player   = _MockPlayer();
      final fallback = _MockFallback();
      final ws       = _MockWs();
      completeCtrl   = StreamController<TtsCompleteEvent>.broadcast();
      errorCtrl      = StreamController<TtsErrorEvent>   .broadcast();

      when( () => player.completeStream ).thenAnswer( ( _ ) => completeCtrl.stream );
      when( () => player.errorStream    ).thenAnswer( ( _ ) => errorCtrl   .stream );
      when( () => player.isPlaying      ).thenReturn( false );
      when( () => player.stop()         ).thenAnswer( ( _ ) async {} );
      when( () => fallback.stopFallbackSpeech() ).thenAnswer( ( _ ) async {} );
      when( () => ws.sessionId ).thenReturn( 'wise penguin' );

      orch = TtsOrchestrator( player: player, fallback: fallback, prefs: prefs, ws: ws );

      recorder      = _MockRecorder();
      final tempDir = await Directory.systemTemp.createTemp( 'voice-reply-dispose-' );
      addTearDown( () async { if ( tempDir.existsSync() ) await tempDir.delete( recursive: true ); } );
      when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
      when( () => recorder.isEncoderSupported( any() ) ).thenAnswer( ( _ ) async => true );
      when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( _ ) async {} );
      when( () => recorder.cancel() ).thenAnswer( ( _ ) async {} );

      asr = AsrService(
        dio                : _MockDio(),
        recorder           : recorder,
        tempDirProvider    : () async => tempDir,
        // The production seam, `service_locator.dart` `_dispatchCaptureHold`.
        onCapturingChanged : ( capturing ) { orch.setCaptureHold( capturing ); },
      );
    } );

    tearDown( () async {
      await orch.dispose();
      await completeCtrl.close();
      await errorCtrl   .close();
    } );

    testWidgets( 'navigating away mid-recording releases the recorder AND the TTS hold', ( tester ) async {
      await tester.pumpWidget( MaterialApp(
        home: Scaffold( body: VoiceReplyField(
          asr                  : asr,
          onSubmit             : ( _ ) {},
          requestMicPermission : () async => true,
        ) ),
      ) );

      await tester.tap( find.byKey( const Key( TestKeys.voiceReplyMic ) ) );
      await tester.pump();
      expect( asr.isCapturing,    isTrue );
      expect( orch.isCaptureHeld, isTrue, reason: 'the mic is open, so speech is held' );

      // Navigating away: the composer's element is gone and dispose() runs.
      await tester.pumpWidget( const MaterialApp( home: Scaffold( body: SizedBox() ) ) );
      await tester.pump();

      expect( find.byType( VoiceReplyField ), findsNothing );
      expect( asr.isCapturing, isFalse,
          reason: 'THE BUG: an ABANDONED capture left _activePath set on the singleton, '
                  'so every later startRecording() threw' );
      expect( orch.isCaptureHeld, isFalse,
          reason: 'THE BUG: TTS stayed silent for the rest of the app session, with no indicator' );
      verify( () => recorder.cancel() ).called( 1 );
    } );
  } );
}
