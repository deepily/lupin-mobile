/// Rick 2026-09-18, before his emulator test drive: three things on the check
/// list (src/rnd/2026.09.18-emulator-ui-check-list.md, items 3, 4 and 6) were
/// pinned only below the screen — the bloc logic, or the split component on
/// its own. Nothing proved FocusModeScreen actually wires them up.
///
/// These tests drive the REAL FocusChatBloc through the REAL screen, with only
/// the network (NotificationRepository, DocRepository), the recorder and the
/// speaker faked:
///   - the toolbar refresh button brings in a seat spawned since cold start;
///   - sending a message to a quiet seat pulls it back onto the Live rail;
///   - a doc link in a bubble halves the conversation, not just opens a viewer.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/auth/domain/auth_bloc.dart';
import 'package:lupin_mobile/features/auth/domain/auth_event.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_mode_screen.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo      extends Mock implements NotificationRepository {}
class _MockTts       extends Mock implements TtsOrchestrator {}
class _MockAsr       extends Mock implements AsrService {}
class _MockAuthBloc  extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}
class _MockNotifBloc extends MockBloc<NotificationEvent, NotificationState>
    implements NotificationBloc {}

class _FakeDocRepository implements DocRepository {
  DocLink? lastRequested;

  @override
  Future<DocContent> fetch( DocLink link ) async {
    lastRequested = link;
    return const DocContent( kind: DocContentKind.markdown, mediaType: 'text/markdown', text: '# How to' );
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

const String _written = 'claude.code@lupin.deepily.ai#d1e0fd28';           // has messaged him
const String _spawned = 'claude.code@lupin-mobile.deepily.ai#7e82da5f';   // live, never has
const String _email   = 'ricardo.felipe.ruiz@gmail.com';
const String _link    = '[Open: how-to](/app/docs?path=lupin-mobile/src/rnd/2026.09.16-phone-install-and-record-how-to.md)';

const MethodChannel _permissions = MethodChannel( 'flutter.baseflow.com/permissions/methods' );
const int _microphone = 7;   // Permission.microphone.value
const int _granted    = 1;   // PermissionStatus.granted.value

void main() {
  late _MockRepo          repo;
  late _MockTts           tts;
  late _MockAsr           asr;
  late _MockAuthBloc      authBloc;
  late _MockNotifBloc     notifBloc;
  late _FakeDocRepository docs;
  late DateTime           clock;
  FocusChatBloc?          bloc;

  setUpAll( () {
    registerFallbackValue( const NotifyRequest( message: 'f', targetUser: 'f' ) );
  } );

  setUp( () {
    repo      = _MockRepo();
    tts       = _MockTts();
    asr       = _MockAsr();
    authBloc  = _MockAuthBloc();
    notifBloc = _MockNotifBloc();
    docs      = _FakeDocRepository();
    clock     = DateTime.utc( 2026, 9, 18, 15 );
    GetIt.instance.registerSingleton<DocRepository>( docs );

    whenListen( authBloc, const Stream<AuthState>.empty(),
        initialState: const AuthAuthenticated( userId: 'u1', email: _email, accessToken: 'tok' ) );
    whenListen( notifBloc, const Stream<NotificationState>.empty(),
        initialState: const NotificationsInitial() );

    when( () => tts.pausedStream     ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    when( () => tts.isPaused         ).thenReturn( false );
    when( () => tts.queueDepth       ).thenReturn( 0 );

    when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
    when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
    when( () => asr.isCapturing       ).thenReturn( false );

    when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => const [] );
    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async => const [] );

    // The composer asks the OS for the microphone; answer "granted".
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler( _permissions, ( call ) async =>
            call.method == 'requestPermissions' ? { _microphone: _granted } : null );
  } );

  tearDown( () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler( _permissions, null );
    await bloc?.close();
    bloc = null;
    await GetIt.instance.reset();
  } );

  /// The senders the server says have written to him, all carrying a persona
  /// so the default Personas rail scope shows them.
  void written( DateTime lastActivity ) {
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async => [
          SenderSummary(
            senderId     : _written,
            lastActivity : lastActivity,
            count        : 3,
            voicePersona : const VoicePersona( name: 'Mr. Radio', icon: '🦉' ),
          ),
        ] );
  }

  /// Let the bloc's awaited repository calls land and the tree rebuild.
  Future<void> settle( WidgetTester tester ) async {
    for ( var i = 0; i < 5; i++ ) {
      await tester.pump( const Duration( milliseconds: 20 ) );
    }
  }

  Future<void> pumpScreen( WidgetTester tester, { Size screen = const Size( 412, 915 ) } ) async {
    tester.view.physicalSize     = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );

    bloc = FocusChatBloc( repo, tts: tts, now: () => clock );
    await tester.pumpWidget( MultiBlocProvider(
      providers: [
        BlocProvider<FocusChatBloc>.value( value: bloc! ),
        BlocProvider<AuthBloc>.value( value: authBloc ),
        BlocProvider<NotificationBloc>.value( value: notifBloc ),
      ],
      child: MaterialApp( home: FocusModeScreen( tts: tts, asr: asr ) ),
    ) );
    await settle( tester );   // the screen's own cold start
  }

  Finder byKey( String k ) => find.byKey( Key( k ) );
  Finder railBadge( String sid ) => byKey( '${TestKeys.focusRailBadgePrefix}$sid' );

  testWidgets( 'item 3 — the toolbar refresh button brings in a seat spawned since cold start', ( tester ) async {
    written( clock.subtract( const Duration( minutes: 5 ) ) );
    await pumpScreen( tester );

    expect( railBadge( _written ), findsOneWidget );
    expect( railBadge( _spawned ), findsNothing, reason: 'not spawned yet at cold start' );

    when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => [
      ActiveSession(
        sessionId : 'sess',
        senderId  : _spawned,
        persona   : const VoicePersona( name: 'Tiffany', icon: '💍' ),
        lastSeen  : clock,
      ),
    ] );
    await tester.tap( byKey( TestKeys.focusRosterRefreshButton ) );
    await settle( tester );

    expect( railBadge( _spawned ), findsOneWidget,
        reason: 'a seat that has never written is on the rail after one tap' );
    expect( railBadge( _written ), findsOneWidget );
  } );

  testWidgets( 'item 4 — sending a message to a quiet seat pulls it back onto the Live rail', ( tester ) async {
    written( clock.subtract( const Duration( minutes: 90 ) ) );   // past the 1-hour Live window
    when( () => repo.notify( any() ) ).thenAnswer( ( _ ) async =>
        NotifyDispatchResponse.fromJson( { 'status': 'queued', 'target_user': 'cc', 'connection_count': 1 } ) );
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'you there?' );
    await pumpScreen( tester );

    expect( railBadge( _written ), findsNothing, reason: 'setup: quiet for 90 minutes, so not Live' );
    expect( find.text( 'Live (0)' ), findsOneWidget );

    // Find it under History, focus it, and speak a message to it.
    await tester.tap( byKey( TestKeys.focusFilterHistory ) );
    await settle( tester );
    await tester.tap( railBadge( _written ) );
    await settle( tester );
    expect( find.text( 'Direct message to Mr. Radio' ), findsOneWidget );

    await tester.tap( byKey( TestKeys.voiceReplyMic ) );   // start
    await settle( tester );
    await tester.tap( byKey( TestKeys.voiceReplyMic ) );   // stop → review
    await settle( tester );
    expect( find.text( 'you there?' ), findsOneWidget );
    await tester.tap( byKey( TestKeys.voiceReplySend ) );
    await settle( tester );

    final sent = verify( () => repo.notify( captureAny() ) ).captured.single as NotifyRequest;
    expect( sent.message, 'you there?' );

    // The focused seat is always on the rail, so its badge proves nothing
    // here; the Live count on the filter bar is what the send must move.
    expect( find.text( 'Live (1)' ), findsOneWidget,
        reason: 'the seat he just wrote to is Live again' );
  } );

  testWidgets( 'item 4 — a failed send leaves the seat off the Live rail', ( tester ) async {
    written( clock.subtract( const Duration( minutes: 90 ) ) );
    when( () => repo.notify( any() ) ).thenThrow(
        const NotificationApiException( 'Notify dispatch failed', statusCode: 401 ) );
    when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'you there?' );
    await pumpScreen( tester );

    await tester.tap( byKey( TestKeys.focusFilterHistory ) );
    await settle( tester );
    await tester.tap( railBadge( _written ) );
    await settle( tester );
    await tester.tap( byKey( TestKeys.voiceReplyMic ) );
    await settle( tester );
    await tester.tap( byKey( TestKeys.voiceReplyMic ) );
    await settle( tester );
    await tester.tap( byKey( TestKeys.voiceReplySend ) );
    await settle( tester );

    expect( find.text( 'Live (0)' ), findsOneWidget,
        reason: 'a send that failed is not activity' );
  } );

  group( 'item 6 — a doc link in a bubble halves the conversation', () {
    Future<void> openLink( WidgetTester tester, Size screen ) async {
      written( clock.subtract( const Duration( minutes: 5 ) ) );
      when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => [
            ConversationMessage.fromJson( {
              'id'        : 'n1',
              'sender_id' : _written,
              'message'   : 'The how-to is ready',
              'type'      : 'custom',
              'priority'  : 'high',
              'state'     : 'delivered',
              'abstract'  : _link,
              'timestamp' : clock.subtract( const Duration( minutes: 5 ) ).toIso8601String(),
            } ),
          ] );
      await pumpScreen( tester, screen: screen );

      await tester.tap( railBadge( _written ) );
      await settle( tester );
      expect( find.text( 'The how-to is ready' ), findsOneWidget );

      await tester.tap( find.textContaining( 'Open: how-to' ) );
      await settle( tester );

      expect( find.byType( DocViewerScreen ), findsOneWidget );
      expect( docs.lastRequested!.relPath, 'src/rnd/2026.09.16-phone-install-and-record-how-to.md' );
    }

    testWidgets( 'unfolded (840 wide): the conversation shrinks to the left half', ( tester ) async {
      await openLink( tester, const Size( 840, 900 ) );

      final pane   = tester.getRect( find.byType( FocusChatPane ) );
      final viewer = tester.getRect( find.byType( DocViewerScreen ) );
      expect( pane.right, lessThanOrEqualTo( 420 + 1 ),
          reason: 'the bubbles live in the LEFT half, not full width behind the document' );
      expect( viewer.left, greaterThanOrEqualTo( 420 - 1 ) );
    } );

    testWidgets( 'phone (412 wide): the conversation shrinks to the top half, full width', ( tester ) async {
      await openLink( tester, const Size( 412, 915 ) );

      final pane   = tester.getRect( find.byType( FocusChatPane ) );
      final viewer = tester.getRect( find.byType( DocViewerScreen ) );
      expect( pane.bottom, lessThanOrEqualTo( viewer.top + 1 ),
          reason: 'stacked: conversation above, document below' );
      expect( viewer.width, closeTo( 412, 1 ) );
    } );
  } );
}
