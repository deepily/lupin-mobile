import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/shared/widgets/dictation_text_field.dart';

class _MockAsr extends Mock implements AsrService {}

/// Row c67f9781, step 0: the widget's own behavior, against a fake service.
///
/// `tester.enterText` always leaves the caret at the END, so every caret case
/// here sets `controller.value` directly.
void main() {
  late _MockAsr asr;

  setUp( () {
    asr = _MockAsr();
    when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
    when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
  } );

  const micKey    = Key( 't.mic' );
  const cancelKey = Key( 't.cancel' );

  Widget field( TextEditingController c, {
    AsrService? service,
    bool granted = true,
    bool enabled = true,
    Key? mic = micKey,
    Key? fieldKey,
  } ) => DictationTextField(
    controller           : c,
    asr                  : service,
    requestMicPermission : () async => granted,
    enabled              : enabled,
    micKey               : mic,
    cancelKey            : cancelKey,
    fieldKey             : fieldKey,
  );

  Widget host( Widget child ) => MaterialApp( home: Scaffold( body: child ) );

  Future<void> tapMic( WidgetTester t, [ Key k = micKey ] ) async {
    await t.tap( find.byKey( k ) );
    await t.pump();
  }

  Future<void> settle( WidgetTester t ) async {
    await t.pump();
    await t.pump( const Duration( milliseconds: 20 ) );
  }

  testWidgets( 'permission refused: error text, nothing recorded', ( t ) async {
    final c = TextEditingController( text: 'kept' );
    await t.pumpWidget( host( field( c, service: asr, granted: false ) ) );
    await tapMic( t );

    expect( find.textContaining( 'permission' ), findsOneWidget );
    expect( c.text, 'kept' );
    verifyNever( () => asr.startRecording() );
  } );

  testWidgets( 'dispose while listening cancels the recorder', ( t ) async {
    final c = TextEditingController();
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    await t.pumpWidget( host( const SizedBox() ) );

    verify( () => asr.cancelRecording() ).called( 1 );
  } );

  testWidgets( 'dispose while transcribing drops the result, nothing lands', ( t ) async {
    final gate = Completer<String>();
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );
    final c = TextEditingController( text: 'a' );
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    await tapMic( t );
    await t.pumpWidget( host( const SizedBox() ) );
    gate.complete( 'late words' );
    await settle( t );

    expect( c.text, 'a' );
    expect( t.takeException(), isNull );
  } );

  testWidgets( 'caret in the middle: words land at the caret', ( t ) async {
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'middle' );
    final c = TextEditingController();
    c.value = const TextEditingValue(
      text: 'head tail', selection: TextSelection.collapsed( offset: 5 ) );
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    await tapMic( t );
    await settle( t );

    expect( c.text, 'head middle tail' );
  } );

  testWidgets( 'edit during recording: words go to the END (Chloé M1)', ( t ) async {
    final gate = Completer<String>();
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );
    final c = TextEditingController();
    c.value = const TextEditingValue(
      text: 'the quikc fox', selection: TextSelection.collapsed( offset: 9 ) );
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    c.value = const TextEditingValue(
      text: 'the quick fox', selection: TextSelection.collapsed( offset: 9 ) );
    await tapMic( t );
    gate.complete( 'jumps' );
    await settle( t );

    expect( c.text, 'the quick fox jumps' );
  } );

  testWidgets( 'blank transcript: value unchanged, selection included', ( t ) async {
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => '  ' );
    final c = TextEditingController();
    c.value = const TextEditingValue(
      text: 'abc def', selection: TextSelection.collapsed( offset: 3 ) );
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    await tapMic( t );
    await settle( t );

    expect( c.text, 'abc def' );
    expect( c.selection.baseOffset, 3 );
    expect( find.textContaining( 'Did not catch' ), findsOneWidget );
  } );

  testWidgets( 'two boxes, one recorder: the second mic is disabled', ( t ) async {
    final a = TextEditingController();
    final b = TextEditingController();
    await t.pumpWidget( host( Column( children: [
      field( a, service: asr, mic: const Key( 't.a' ) ),
      field( b, service: asr, mic: const Key( 't.b' ) ),
    ] ) ) );
    await t.tap( find.byKey( const Key( 't.a' ) ) );
    await t.pump();

    final second = t.widget<IconButton>( find.byKey( const Key( 't.b' ) ) );
    expect( second.onPressed, isNull );
    await t.tap( find.byKey( const Key( 't.b' ) ), warnIfMissed: false );
    await t.pump();
    verify( () => asr.startRecording() ).called( 1 );
  } );

  testWidgets( 'stale result still frees the mic', ( t ) async {
    final gate = Completer<String>();
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) => gate.future );
    final c = TextEditingController( text: 'x' );
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    await tapMic( t );
    await tapMic( t, cancelKey );
    gate.complete( 'too late' );
    await settle( t );

    expect( c.text, 'x' );
    expect( t.widget<IconButton>( find.byKey( micKey ) ).onPressed, isNotNull );
  } );

  testWidgets( 'no asr and no scope: no mic, a plain TextField', ( t ) async {
    final c = TextEditingController();
    await t.pumpWidget( host( field( c ) ) );

    expect( find.byKey( micKey ), findsNothing );
    expect( find.byType( TextField ), findsOneWidget );
  } );

  testWidgets( 'a DictationScope supplies the service', ( t ) async {
    final c = TextEditingController();
    await t.pumpWidget( host( DictationScope( asr: asr, child: field( c ) ) ) );

    expect( find.byKey( micKey ), findsOneWidget );
  } );

  testWidgets( 'enabled: false disables the mic', ( t ) async {
    final c = TextEditingController();
    await t.pumpWidget( host( field( c, service: asr, enabled: false ) ) );

    expect( t.widget<IconButton>( find.byKey( micKey ) ).onPressed, isNull );
  } );

  testWidgets( 'a parent rebuild keeps the session, so a recording survives it', ( t ) async {
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'kept' );
    final c = TextEditingController();
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    await t.pumpWidget( host( field( c, service: asr ) ) );
    await tapMic( t );
    await settle( t );

    expect( c.text, 'kept' );
    verifyNever( () => asr.cancelRecording() );
  } );
}

