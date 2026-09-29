import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/asr/voice_capture_session.dart';
import 'package:lupin_mobile/shared/widgets/prompt_bodies.dart';

class _MockAsr extends Mock implements AsrService {}

/// Row 570c2fce, the SECOND box (Rick via Tiffany, 2026-09-28): the "Your
/// response" box on a prompt card gets the same microphone the Focus composer
/// got — it records a chunk and APPENDS it to the answer.
///
/// Same shared `spliceDictation` rule, so the two boxes cannot drift, and the
/// same guarantee on every failure path: the answer already typed survives.
void main() {
  late _MockAsr        asr;
  late List<String>    responded;

  setUp( () {
    asr       = _MockAsr();
    responded = [];
    when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
    when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
  } );

  VoiceCaptureSession session( { bool granted = true } ) => VoiceCaptureSession(
    asr               : asr,
    requestPermission : () async => granted,
  );

  Widget host( { VoiceCaptureSession? voice } ) => MaterialApp(
    home: Scaffold(
      body: OpenEndedPromptBody( onRespond: responded.add, voice: voice ),
    ),
  );

  Finder byKeyStr( String k ) => find.byKey( Key( k ) );

  TextEditingController boxOf( WidgetTester tester ) =>
      tester.widget<TextField>( byKeyStr( TestKeys.promptResponseField ) ).controller!;

  Future<void> dictate( WidgetTester tester ) async {
    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();
    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 20 ) );
  }

  testWidgets( 'NO recorder, NO microphone — the box is exactly the one that shipped', ( tester ) async {
    await tester.pumpWidget( host() );

    expect( byKeyStr( TestKeys.promptResponseMic ), findsNothing );
    expect( find.text( 'Submit' ), findsOneWidget );

    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'typed only' );
    await tester.tap( find.text( 'Submit' ) );
    await tester.pump();
    expect( responded, [ 'typed only' ] );
  } );

  testWidgets( 'the dictated chunk is APPENDED to what was already typed', ( tester ) async {
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'and the rest out loud' );

    await tester.pumpWidget( host( voice: session() ) );
    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'half typed' );
    await tester.pump();
    await dictate( tester );

    expect( boxOf( tester ).text, 'half typed and the rest out loud' );
    expect( responded, isEmpty, reason: 'dictating is not answering' );
  } );

  testWidgets( 'into an empty box the answer stands alone, and a SECOND chunk follows the first', ( tester ) async {
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'chunk' );

    await tester.pumpWidget( host( voice: session() ) );
    await dictate( tester );
    expect( boxOf( tester ).text, 'chunk' );

    await dictate( tester );
    expect( boxOf( tester ).text, 'chunk chunk' );
  } );

  testWidgets( 'the answer is submitted with the dictated text, once', ( tester ) async {
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'spoken answer' );

    await tester.pumpWidget( host( voice: session() ) );
    await dictate( tester );
    await tester.tap( find.text( 'Submit' ) );
    await tester.pump();

    expect( responded, [ 'spoken answer' ] );
  } );

  testWidgets( 'PERMISSION DENIED: guidance inline, the typed answer untouched, recorder never started', ( tester ) async {
    await tester.pumpWidget( host( voice: session( granted: false ) ) );
    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'my answer' );
    await tester.pump();

    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();

    expect( byKeyStr( TestKeys.promptResponseMicError ), findsOneWidget );
    expect( find.textContaining( 'permission' ), findsOneWidget );
    expect( boxOf( tester ).text, 'my answer' );
    verifyNever( () => asr.startRecording() );
  } );

  testWidgets( 'CANCELLED: the recording is discarded, the answer is not, and Submit comes back', ( tester ) async {
    await tester.pumpWidget( host( voice: session() ) );
    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'keep me' );
    await tester.pump();

    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();
    expect( find.textContaining( 'Recording…' ), findsOneWidget );
    expect( find.text( 'Submit' ), findsNothing,
        reason: 'a half-dictated answer cannot be sent by a stray thumb' );

    await tester.tap( byKeyStr( TestKeys.promptResponseMicCancel ) );
    await tester.pump();

    verify( () => asr.cancelRecording() ).called( 1 );
    verifyNever( () => asr.stopAndTranscribe() );
    expect( boxOf( tester ).text, 'keep me' );
    expect( find.text( 'Submit' ), findsOneWidget );
  } );

  testWidgets( 'ASR ERROR leaves the answer untouched and says what went wrong', ( tester ) async {
    when( () => asr.stopAndTranscribe() )
        .thenThrow( const AsrException( 'Transcription upload failed: timeout' ) );

    await tester.pumpWidget( host( voice: session() ) );
    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'half an answer' );
    await tester.pump();
    await dictate( tester );

    expect( boxOf( tester ).text, 'half an answer' );
    expect( find.textContaining( 'upload failed' ), findsOneWidget );
    expect( find.byType( CircularProgressIndicator ), findsNothing, reason: 'no stuck spinner' );
    expect( responded, isEmpty );
  } );

  testWidgets( 'NEGATIVE CONTROL — a capture that heard nothing appends nothing and does not blank the box', ( tester ) async {
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => '   ' );

    await tester.pumpWidget( host( voice: session() ) );
    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'untouched' );
    await tester.pump();
    await dictate( tester );

    expect( boxOf( tester ).text, 'untouched' );
    expect( find.textContaining( 'Did not catch anything' ), findsOneWidget );
  } );

  testWidgets( 'a typo fixed WHILE talking does not drag the sentence into the middle (Chloé M1)', ( tester ) async {
    final gate = Completer<String>();
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );

    await tester.pumpWidget( host( voice: session() ) );
    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'the quikc brown fox' );
    await tester.pump();
    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();

    // The caret stays where the typo was fixed — offset 9, just after the
    // corrected word, nowhere near the end.
    boxOf( tester ).value = const TextEditingValue(
      text      : 'the quick brown fox',
      selection : TextSelection.collapsed( offset: 9 ),
    );
    await tester.pump();

    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();
    gate.complete( 'jumps over the lazy dog' );
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 20 ) );

    expect( boxOf( tester ).text, 'the quick brown fox jumps over the lazy dog',
        reason: 'the same trap the composer had: an edit invalidates the remembered caret' );
  } );

  testWidgets( 'a cancel that overtakes an in-flight transcribe appends nothing and frees the mic', ( tester ) async {
    final gate = Completer<String>();
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );

    await tester.pumpWidget( host( voice: session() ) );
    await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'answer' );
    await tester.pump();
    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();
    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();
    expect( find.byType( CircularProgressIndicator ), findsOneWidget );
    expect( find.text( 'Submit' ), findsNothing );

    await tester.tap( byKeyStr( TestKeys.promptResponseMicCancel ) );
    await tester.pump();
    gate.complete( 'too late' );
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 20 ) );

    expect( boxOf( tester ).text, 'answer' );
    expect( byKeyStr( TestKeys.promptResponseMic ), findsOneWidget );
    expect( find.text( 'Submit' ), findsOneWidget );
  } );

  testWidgets( 'leaving the card mid-recording cancels the capture rather than stranding the hold', ( tester ) async {
    await tester.pumpWidget( host( voice: session() ) );
    await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
    await tester.pump();

    await tester.pumpWidget( const MaterialApp( home: Scaffold( body: SizedBox() ) ) );
    await tester.pump();

    verify( () => asr.cancelRecording() ).called( 1 );
  } );

  // ── Row 928c5808: the widget builds and OWNS its session from the service ──
  group( 'given the SERVICE, the box owns its own session', () {
    Widget owned( { bool granted = true } ) => MaterialApp(
      home: Scaffold(
        body: OpenEndedPromptBody(
          onRespond            : responded.add,
          asr                  : asr,
          requestMicPermission : () async => granted,
        ),
      ),
    );

    testWidgets( 'the mic appears and a dictated chunk is appended', ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'said aloud' );

      await tester.pumpWidget( owned() );
      await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'typed' );
      await tester.pump();
      await dictate( tester );

      expect( boxOf( tester ).text, 'typed said aloud' );
    } );

    testWidgets( 'closing the box mid-recording cancels the recorder ITSELF — no ancestor involved',
        ( tester ) async {
      await tester.pumpWidget( owned() );
      await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
      await tester.pump();
      verify( () => asr.startRecording() ).called( 1 );

      // The sheet goes away: nothing above the box holds a session to cancel.
      await tester.pumpWidget( const MaterialApp( home: Scaffold() ) );

      verify( () => asr.cancelRecording() ).called( 1 );
    } );

    testWidgets( 'a rebuild of the parent keeps the SAME session, so a recording survives it',
        ( tester ) async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'kept' );

      await tester.pumpWidget( owned() );
      await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
      await tester.pump();
      await tester.pumpWidget( owned() );   // parent rebuilds with a fresh widget
      await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 20 ) );

      expect( boxOf( tester ).text, 'kept' );
      verifyNever( () => asr.cancelRecording() );
    } );

    testWidgets( 'permission refused: nothing records and the draft is untouched', ( tester ) async {
      await tester.pumpWidget( owned( granted: false ) );
      await tester.enterText( byKeyStr( TestKeys.promptResponseField ), 'my draft' );
      await tester.pump();
      await tester.tap( byKeyStr( TestKeys.promptResponseMic ) );
      await tester.pump();

      verifyNever( () => asr.startRecording() );
      expect( boxOf( tester ).text, 'my draft' );
      expect( byKeyStr( TestKeys.promptResponseMicError ), findsOneWidget );
    } );
  } );
}
