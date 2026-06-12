import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/voice_reply_field.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';

class _MockAsr extends Mock implements AsrService {}

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
  } );
}
