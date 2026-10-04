/// Row f1e80e67 (plan §7.5) — long-press a Focus bubble to mute its sender.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

class _MockBloc extends Mock implements FocusChatBloc {}

const String _sender = 'claude.code@lupin.deepily.ai#d1e0fd28';
const String _key    = 'persona:maya';

NotificationItem _item() => NotificationItem(
  id                     : 'n1',
  message                : 'hello from maya',
  type                   : 'task',
  priority               : 'high',
  senderId               : _sender,
  timestamp              : DateTime( 2026, 9, 29, 9 ),
  played                 : true,
  playCount              : 0,
  responseRequested      : false,
  suppressDing           : true,
  displayQualifierWidget : false,
);

void main() {
  late _MockBloc              bloc;
  late NotificationPreferences prefs;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    prefs = NotificationPreferences( await SharedPreferences.getInstance() );
    bloc  = _MockBloc();
    when( () => bloc.close() ).thenAnswer( ( _ ) async {} );
    final st = const FocusChatState.initial().copyWith(
      senderOrder      : const [ _sender ],
      focusedSender    : _sender,
      windows          : { _sender: [ FocusMessage( item: _item() ) ] },
      personasBySender : { _sender: const VoicePersona( name: 'Maya', icon: '🌻' ) },
      hydration        : FocusHydration.ready,
      asOf             : DateTime( 2026, 9, 29, 9 ),
    );
    when( () => bloc.state ).thenReturn( st );
    when( () => bloc.stream ).thenAnswer( ( _ ) => const Stream<FocusChatState>.empty() );
  } );

  Future<void> mount( WidgetTester tester ) async {
    await tester.pumpWidget( MaterialApp( home: Scaffold(
      body: BlocProvider<FocusChatBloc>.value(
        value : bloc,
        child : FocusChatPane( userEmail: 'rick@test.com', prefs: prefs ),
      ),
    ) ) );
    await tester.pump();
  }

  Future<void> longPress( WidgetTester tester ) async {
    await tester.longPress( find.byKey( const Key( '${TestKeys.focusBubblePrefix}n1' ) ) );
    await tester.pumpAndSettle();
  }

  testWidgets( 'long-press offers Mute <label>; choosing it writes the key', ( tester ) async {
    await mount( tester );
    await longPress( tester );

    expect( find.text( 'Mute 🌻 Maya' ), findsOneWidget );
    await tester.tap( find.byKey( const Key( TestKeys.senderMuteAction ) ) );
    await tester.pumpAndSettle();

    expect( prefs.isSenderMuted( _key ), isTrue );
    expect( prefs.mutedSenders[ _key ], '🌻 Maya' );
    expect( find.text( 'Muted 🌻 Maya' ), findsOneWidget );
  } );

  testWidgets( 'Undo in the SnackBar removes the mute', ( tester ) async {
    await mount( tester );
    await longPress( tester );
    await tester.tap( find.byKey( const Key( TestKeys.senderMuteAction ) ) );
    await tester.pumpAndSettle();
    expect( prefs.isSenderMuted( _key ), isTrue );

    await tester.tap( find.byKey( const Key( TestKeys.senderMuteUndo ) ) );
    await tester.pumpAndSettle();
    expect( prefs.isSenderMuted( _key ), isFalse );
  } );

  testWidgets( 'an already-muted sender is offered Unmute, and Undo re-mutes', ( tester ) async {
    await prefs.muteSender( _key, '🌻 Maya' );
    await mount( tester );
    await longPress( tester );

    expect( find.text( 'Mute 🌻 Maya' ), findsNothing );
    expect( find.text( 'Unmute 🌻 Maya' ), findsOneWidget );
    await tester.tap( find.byKey( const Key( TestKeys.senderUnmuteAction ) ) );
    await tester.pumpAndSettle();
    expect( prefs.isSenderMuted( _key ), isFalse );

    await tester.tap( find.byKey( const Key( TestKeys.senderMuteUndo ) ) );
    await tester.pumpAndSettle();
    expect( prefs.isSenderMuted( _key ), isTrue );
  } );

  testWidgets( 'dismissing the sheet changes nothing', ( tester ) async {
    await mount( tester );
    await longPress( tester );
    await tester.tapAt( const Offset( 5, 5 ) );   // scrim
    await tester.pumpAndSettle();
    expect( prefs.mutedSenders, isEmpty );
  } );
}
