/// AC-S3.8 / testing-strategy §Cross-Section item 3 — S3 ASSEMBLY test:
/// REAL FocusChatBloc behind the real screen; a rail tap switches the
/// focused pane WITHOUT dispatching any TTS state change (Q4 manual-focus
/// invariant, end-to-end through the assembled surface).
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/auth/domain/auth_bloc.dart';
import 'package:lupin_mobile/features/auth/domain/auth_event.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_mode_screen.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}
class _MockTts  extends Mock implements TtsOrchestrator {}
class _MockAsr  extends Mock implements AsrService {}
class _MockRepo extends Mock implements NotificationRepository {}

NotificationItem _item( String id, String sender ) {
  return NotificationItem(
    id                     : id,
    message                : 'msg-$id',
    type                   : 'task',
    priority               : 'low',
    senderId               : sender,
    timestamp              : DateTime( 2026, 6, 12, 1 ),
    played                 : false,
    playCount              : 0,
    responseRequested      : false,
    suppressDing           : false,
    displayQualifierWidget : false,
  );
}

void main() {
  testWidgets( 'Cross-Section checkpoint 3 — rail tap switches the pane with ZERO TTS state changes', ( tester ) async {
    final tts        = _MockTts();
    final asr        = _MockAsr();
    final authBloc   = _MockAuthBloc();
    final repo       = _MockRepo();
    final pausedCtrl = StreamController<bool>.broadcast();
    final depthCtrl  = StreamController<int>.broadcast();

    when( () => tts.pausedStream     ).thenAnswer( ( _ ) => pausedCtrl.stream );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => depthCtrl.stream );
    when( () => tts.isPaused         ).thenReturn( false );
    when( () => tts.queueDepth       ).thenReturn( 0 );

    // Defensive: should the screen's init-guard ever dispatch a cold start,
    // an UN-stubbed mock would throw MissingStubError inside the bloc's
    // event zone (poisoning the test opaquely) — stub to benign empties.
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) ).thenAnswer( ( _ ) async => const [] );
    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async => const [] );

    whenListen( authBloc, const Stream<AuthState>.empty(),
        initialState: const AuthAuthenticated(
          userId      : 'u1',
          email       : 'rick@test.com',
          accessToken : 'tok',
        ) );

    // REAL bloc, seeded through real inbound events. Seeding is genuinely
    // async (bloc event-stream processing), so it runs on the REAL event
    // loop via runAsync — a bare `Future.delayed` under testWidgets fake
    // async never completes (hangs to the 10-min timeout).
    final bloc = FocusChatBloc( repo, tts: tts );
    await tester.runAsync( () async {
      bloc.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );   // persona-less fixtures (§5f)
      bloc.add( FocusInboundNotification( _item( 'a1', 'A' ) ) );
      bloc.add( FocusInboundNotification( _item( 'b1', 'B' ) ) );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );
    } );
    expect( bloc.state.senderOrder, [ 'A', 'B' ],
        reason: 'seeding completed BEFORE the surface pumps (hard gate)' );
    clearInteractions( tts );   // discard the seeding enqueues; the TAP is under test

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<FocusChatBloc>.value( value: bloc ),
          BlocProvider<AuthBloc>.value( value: authBloc ),
        ],
        child: MaterialApp( home: FocusModeScreen( tts: tts, asr: asr ) ),
      ),
    );
    await tester.pump();
    expect( find.textContaining( 'Tap a session badge' ), findsOneWidget );

    await tester.tap( find.byKey( Key( '${TestKeys.focusRailBadgePrefix}B' ) ) );
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 20 ) );

    expect( find.text( 'msg-b1' ), findsOneWidget, reason: 'pane switched to B' );
    expect( find.text( 'msg-a1' ), findsNothing );
    expect( bloc.state.focusedSender, 'B' );

    // Q4: focusing is a VIEWPORT change — zero TTS state mutations.
    verifyNever( () => tts.pause()  );
    verifyNever( () => tts.resume() );
    verifyNever( () => tts.stopAll() );
    verifyNever( () => tts.enqueueAlways(
      priority : any( named: 'priority' ),
      message  : any( named: 'message' ),
      title    : any( named: 'title' ),
      voiceId  : any( named: 'voiceId' ),
      sender   : any( named: 'sender' ),
    ) );

    // Real-event-loop teardown for the same fake-async reason as seeding.
    await tester.runAsync( () async {
      await bloc.close();
      await pausedCtrl.close();
      await depthCtrl.close();
    } );
  } );
}
