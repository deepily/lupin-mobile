/// Row de12b7bc — two things Rick asked for in focus mode.
///
/// 1. The accent bar on a bubble was keyed to PRIORITY, and `high` is orange,
///    so with Tiffany (yellow), María (pink) and Mr. Radio (orange) on the
///    rail every bubble looked like Mr. Radio's. It now carries the SENDER's
///    colour.
/// 2. The header named the e-mail and session but not the persona. The name
///    now sits between the emoji and the id, bold, with the id italic.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';

class _MockBloc extends Mock implements FocusChatBloc {}

const String _sender  = 'claude.code@lupin.deepily.ai#d1e0fd28';
const Color  _radio   = Color( 0xFFFF6D00 );   // Mr. Radio's orange
const Color  _tiffany = Color( 0xFFFFD600 );   // Tiffany's yellow

NotificationItem _item( String id, { String priority = 'high' } ) => NotificationItem(
  id                     : id,
  message                : 'msg-$id',
  type                   : 'task',
  priority               : priority,
  senderId               : _sender,
  timestamp              : DateTime( 2026, 9, 17, 15 ),
  played                 : true,
  playCount              : 0,
  responseRequested      : false,
  suppressDing           : true,
  displayQualifierWidget : false,
);

FocusChatState _state( { VoicePersona? persona } ) => FocusChatState.initial().copyWith(
  senderOrder      : const [ _sender ],
  focusedSender    : _sender,
  windows          : { _sender: [ FocusMessage( item: _item( 'n1' ) ) ] },
  personasBySender : { _sender: persona },
  hydration        : FocusHydration.ready,
  asOf             : DateTime( 2026, 9, 17, 15 ),
);

void main() {
  late _MockBloc bloc;

  void seed( FocusChatState state ) {
    when( () => bloc.state ).thenReturn( state );
    when( () => bloc.stream ).thenAnswer( ( _ ) => const Stream<FocusChatState>.empty() );
  }

  setUp( () {
    bloc = _MockBloc();
    when( () => bloc.close() ).thenAnswer( ( _ ) async {} );
  } );

  Widget host() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<FocusChatBloc>.value(
        value : bloc,
        child : const FocusChatPane( userEmail: 'ricardo.felipe.ruiz@gmail.com' ),
      ),
    ),
  );

  /// The accent bar is the 3-px Container at the leading edge of the bubble.
  Color? accentOf( WidgetTester tester ) {
    final bar = find.descendant(
      of       : find.byKey( const Key( '${TestKeys.focusBubblePrefix}n1' ) ),
      matching : find.byWidgetPredicate( ( w ) =>
          w is Container && w.constraints?.maxWidth == 3.0 ),
    );
    if ( bar.evaluate().isEmpty ) return null;
    return tester.widget<Container>( bar.first ).color;
  }

  testWidgets( 'the accent bar carries the SENDER colour, not the priority colour', ( tester ) async {
    seed( _state( persona: const VoicePersona( name: 'Mr. Radio', icon: '🦉', color: '#FF6D00' ) ) );
    await tester.pumpWidget( host() );
    await tester.pump();
    expect( accentOf( tester ), _radio );

  } );

  testWidgets( 'the same high-priority message from a different sender gets THAT sender colour',
      ( tester ) async {
    // Same message, same 'high' priority, different sender: the colour moves.
    // Mounted fresh rather than re-pumped, because a BlocBuilder rebuilds off
    // the stream, not off a re-read of `state`.
    seed( _state( persona: const VoicePersona( name: 'Tiffany', icon: '💍', color: '#FFD600' ) ) );
    await tester.pumpWidget( host() );
    await tester.pump();
    expect( accentOf( tester ), _tiffany,
        reason: 'THE BUG: every sender\'s high-priority bubble used to be orange' );
  } );

  testWidgets( 'a sender with no colour keeps the priority palette rather than going colourless',
      ( tester ) async {
    seed( _state( persona: const VoicePersona( name: 'Plain', icon: '🔧' ) ) );
    await tester.pumpWidget( host() );
    await tester.pump();
    expect( accentOf( tester ), Colors.orange, reason: "'high' priority fallback" );
  } );

  testWidgets( 'a malformed colour falls back too, and does not throw', ( tester ) async {
    seed( _state( persona: const VoicePersona( name: 'Broken', icon: '🔧', color: 'not-a-colour' ) ) );
    await tester.pumpWidget( host() );
    await tester.pump();
    expect( accentOf( tester ), Colors.orange );
    expect( tester.takeException(), isNull );
  } );

  testWidgets( 'the header shows the persona name in bold, then the sender id in italic',
      ( tester ) async {
    seed( _state( persona: const VoicePersona( name: 'Mr. Radio', icon: '🦉', color: '#FF6D00' ) ) );
    await tester.pumpWidget( host() );
    await tester.pump();

    final name = tester.widget<Text>( find.byKey( const Key( TestKeys.focusHeaderPersonaName ) ) );
    expect( name.data, 'Mr. Radio' );
    expect( name.style?.fontWeight, FontWeight.bold );

    final id = tester.widget<Text>( find.byKey( const Key( TestKeys.focusHeaderSenderId ) ) );
    expect( id.data, _sender, reason: 'e-mail and session id still shown' );
    expect( id.style?.fontStyle, FontStyle.italic );
  } );

  testWidgets( 'the display name wins over the raw persona name when the server sends one',
      ( tester ) async {
    seed( _state( persona: const VoicePersona(
      name: 'maria', displayName: 'María', icon: '🌸', color: '#F06292' ) ) );
    await tester.pumpWidget( host() );
    await tester.pump();

    expect( tester.widget<Text>(
      find.byKey( const Key( TestKeys.focusHeaderPersonaName ) ) ).data, 'María' );
  } );

  testWidgets( 'a sender with no persona shows the id alone — no empty bold gap', ( tester ) async {
    seed( _state() );
    await tester.pumpWidget( host() );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.focusHeaderPersonaName ) ), findsNothing );
    expect( tester.widget<Text>(
      find.byKey( const Key( TestKeys.focusHeaderSenderId ) ) ).data, _sender );
  } );
}
