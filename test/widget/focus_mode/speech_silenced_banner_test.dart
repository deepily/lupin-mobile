// Row e0f0faf0: Rick heard nothing because Master mute was on, two screens deep, with no sign of it
// on the main screen. The marker shows on the conversation screen whenever a whole-phone silencer is
// active, names each one in plain words, and a tap opens the screen that holds that switch.
//
// In scope: Notifications off, Master mute, TTS slider at 0%, quiet hours in effect now.
// Out of scope by design: per-sender mutes, priority switches, the stop-list.

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/speech_silenced_banner.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState> implements FocusChatBloc {}

void main() {
  late NotificationPreferences prefs;
  late int                     openedNotifications;
  late int                     openedSettings;
  late DateTime                clock;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    prefs               = NotificationPreferences( await SharedPreferences.getInstance() );
    openedNotifications = 0;
    openedSettings      = 0;
    clock               = DateTime( 2026, 10, 10, 12, 0 );
  } );

  Widget host() => MaterialApp( home: Scaffold(
    body: SpeechSilencedBanner(
      prefs               : prefs,
      now                 : () => clock,
      onOpenNotifications : () => openedNotifications++,
      onOpenSettings      : () => openedSettings++,
    ),
  ) );

  final banner   = find.byKey( const Key( TestKeys.focusSilencedBanner ) );
  final mute     = find.byKey( const Key( TestKeys.focusSilencedMasterMute ) );
  final notifOff = find.byKey( const Key( TestKeys.focusSilencedNotificationsOff ) );
  final slider   = find.byKey( const Key( TestKeys.focusSilencedSliderZero ) );
  final quiet    = find.byKey( const Key( TestKeys.focusSilencedQuietHours ) );

  group( 'what counts', () {
    testWidgets( 'nothing silenced: no marker', ( tester ) async {
      await tester.pumpWidget( host() );
      expect( banner, findsNothing );
    } );

    testWidgets( 'Master mute on: the marker says so in plain words', ( tester ) async {
      await prefs.setMasterMute( true );
      await tester.pumpWidget( host() );

      expect( banner, findsOneWidget );
      expect( mute, findsOneWidget );
      expect( find.textContaining( 'Master mute is on' ), findsOneWidget );
      expect( notifOff, findsNothing );
    } );

    testWidgets( 'Notifications off', ( tester ) async {
      await prefs.setEnabled( false );
      await tester.pumpWidget( host() );

      expect( notifOff, findsOneWidget );
      expect( find.textContaining( 'Notifications are off' ), findsOneWidget );
    } );

    testWidgets( 'TTS slider at 0%', ( tester ) async {
      await prefs.setTtsFraction( 0.0 );
      await tester.pumpWidget( host() );

      expect( slider, findsOneWidget );
      expect( find.textContaining( 'TTS slider is at 0%' ), findsOneWidget );
    } );

    testWidgets( 'quiet hours in effect now, and not when the clock is outside the window', ( tester ) async {
      await prefs.setQuietEnabled( true );
      await prefs.setQuietStartMinutes( 22 * 60 );
      await prefs.setQuietEndMinutes( 7 * 60 );

      clock = DateTime( 2026, 10, 10, 23, 30 );
      await tester.pumpWidget( host() );
      expect( quiet, findsOneWidget );
      expect( find.textContaining( 'Quiet hours are in effect' ), findsOneWidget );

      clock = DateTime( 2026, 10, 10, 12, 0 );
      await tester.pump( const Duration( seconds: 2 ) );
      expect( quiet, findsNothing, reason: 'the window is re-evaluated against the clock, not read once' );
    } );

    testWidgets( 'quiet hours with the urgent bypass on says urgent messages still speak', ( tester ) async {
      await prefs.setQuietEnabled( true );
      await prefs.setQuietStartMinutes( 22 * 60 );
      await prefs.setQuietEndMinutes( 7 * 60 );
      clock = DateTime( 2026, 10, 10, 23, 30 );
      expect( prefs.quietUrgentBypass, isTrue, reason: 'the default' );

      await tester.pumpWidget( host() );
      expect( find.textContaining( 'urgent messages still speak' ), findsOneWidget );
    } );

    testWidgets( 'quiet hours with the urgent bypass off does not claim urgent still speaks', ( tester ) async {
      await prefs.setQuietEnabled( true );
      await prefs.setQuietStartMinutes( 22 * 60 );
      await prefs.setQuietEndMinutes( 7 * 60 );
      await prefs.setQuietUrgentBypass( false );
      clock = DateTime( 2026, 10, 10, 23, 30 );

      await tester.pumpWidget( host() );
      expect( quiet, findsOneWidget );
      expect( find.textContaining( 'urgent' ), findsNothing );
    } );

    testWidgets( 'Master mute has no bypass, so its row never mentions urgent', ( tester ) async {
      await prefs.setMasterMute( true );
      await tester.pumpWidget( host() );

      expect( find.textContaining( 'urgent' ), findsNothing );
    } );

    testWidgets( 'several at once: every one is named', ( tester ) async {
      await prefs.setEnabled( false );
      await prefs.setMasterMute( true );
      await prefs.setTtsFraction( 0.0 );
      await tester.pumpWidget( host() );

      expect( notifOff, findsOneWidget );
      expect( mute,     findsOneWidget );
      expect( slider,   findsOneWidget );
    } );

    testWidgets( 'per-sender mutes, priority switches and the stop-list are not whole-phone silencers', ( tester ) async {
      await prefs.setSpeakOnHigh( false );
      await prefs.setSpeakOnUrgent( false );
      await prefs.setSpeakSystemSenders( false );
      await tester.pumpWidget( host() );

      expect( banner, findsNothing );
    } );
  } );

  group( 'live', () {
    testWidgets( 'appears and disappears as the switch changes elsewhere', ( tester ) async {
      await tester.pumpWidget( host() );
      expect( banner, findsNothing );

      await prefs.setMasterMute( true );     // written from another screen
      await tester.pump( const Duration( seconds: 2 ) );
      expect( mute, findsOneWidget );

      await prefs.setMasterMute( false );
      await tester.pump( const Duration( seconds: 2 ) );
      expect( banner, findsNothing );
    } );
  } );

  group( 'one tap opens the screen that holds the switch', () {
    testWidgets( 'Master mute opens Settings', ( tester ) async {
      await prefs.setMasterMute( true );
      await tester.pumpWidget( host() );

      await tester.tap( mute );
      expect( openedSettings, 1 );
      expect( openedNotifications, 0 );
    } );

    testWidgets( 'Notifications off opens Notifications', ( tester ) async {
      await prefs.setEnabled( false );
      await tester.pumpWidget( host() );

      await tester.tap( notifOff );
      expect( openedNotifications, 1 );
      expect( openedSettings, 0 );
    } );

    testWidgets( 'quiet hours opens Notifications', ( tester ) async {
      await prefs.setQuietEnabled( true );
      await prefs.setQuietStartMinutes( 22 * 60 );
      await prefs.setQuietEndMinutes( 7 * 60 );
      clock = DateTime( 2026, 10, 10, 23, 30 );
      await tester.pumpWidget( host() );

      await tester.tap( quiet );
      expect( openedNotifications, 1 );
    } );

    testWidgets( 'the slider row opens nothing: the slider is on this screen', ( tester ) async {
      await prefs.setTtsFraction( 0.0 );
      await tester.pumpWidget( host() );

      await tester.tap( slider );
      expect( openedNotifications, 0 );
      expect( openedSettings, 0 );
    } );
  } );

  group( 'mounted on the main conversation pane', () {
    testWidgets( 'FocusChatPane shows the marker above the TTS bar when Master mute is on', ( tester ) async {
      await prefs.setMasterMute( true );
      final bloc = _MockFocusBloc();
      final st   = const FocusChatState.initial().copyWith( hydration: FocusHydration.ready );
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
      final sl = NotificationStopList( await SharedPreferences.getInstance() );

      await tester.pumpWidget( MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
        value : bloc,
        child : FocusChatPane( userEmail: 'rick@test.com', stopList: sl, prefs: prefs ),
      ) ) ) );
      await tester.pump();

      expect( mute, findsOneWidget );
      expect( find.byKey( const Key( TestKeys.focusTtsFractionBar ) ), findsOneWidget );
      expect( tester.getTopLeft( mute ).dy, lessThan( tester.getTopLeft( find.byKey( const Key( TestKeys.focusTtsFractionBar ) ) ).dy ) );
    } );
  } );
}
