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

  /// What `GET /api/docs/scopes` answers (row 0534b50d).
  List<DocScope> scopes = const [];

  @override
  Future<DocContent> fetch( DocLink link ) async {
    lastRequested = link;
    if ( link.kind == DocLinkKind.io ) {
      return const DocContent(
        kind      : DocContentKind.directory,
        mediaType : 'application/json',
        listing   : DocDirectoryListing( scope: 'io', path: '', parent: null, entries: [] ),
      );
    }
    return const DocContent( kind: DocContentKind.markdown, mediaType: 'text/markdown', text: '# How to' );
  }

  @override
  Future<List<DocScope>> fetchScopes() async => scopes;

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

      // The bubble shows the abstract's row only (progressive disclosure,
      // 2026-09-18); the link is inside the abstract it opens in the split.
      await tester.tap( find.byKey( const Key( TestKeys.abstractOpenButton ) ) );
      await settle( tester );
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

    // Rick 2026-09-18: tapping the abstract's icon did nothing, and the
    // abstract should not render in the bubble at all. The row now opens the
    // whole abstract in the same half a doc link uses.
    testWidgets( 'the abstract icon opens the whole abstract in the split, beside the conversation', ( tester ) async {
      written( clock.subtract( const Duration( minutes: 5 ) ) );
      final abstractText = [
        '# Twelve lines',
        for ( var i = 2; i <= 11; i++ ) 'Line \$i of the abstract.',
        'The very last line.',
      ].join( '\n' );
      when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => [
            ConversationMessage.fromJson( {
              'id'        : 'n2',
              'sender_id' : _written,
              'message'   : 'Here is the summary',
              'type'      : 'custom',
              'priority'  : 'high',
              'state'     : 'delivered',
              'abstract'  : abstractText,
              'timestamp' : clock.subtract( const Duration( minutes: 5 ) ).toIso8601String(),
            } ),
          ] );
      await pumpScreen( tester, screen: const Size( 840, 900 ) );
      await tester.tap( railBadge( _written ) );
      await settle( tester );
      expect( find.textContaining( 'The very last line.' ), findsNothing, reason: 'setup: the bubble shows none of the abstract' );

      await tester.tap( find.byKey( const Key( TestKeys.abstractOpenButton ) ) );
      await settle( tester );

      final viewer = find.byType( DocViewerScreen );
      expect( viewer, findsOneWidget );
      expect( find.descendant( of: viewer, matching: find.textContaining( 'The very last line.' ) ), findsOneWidget );
      expect( tester.getRect( find.byType( FocusChatPane ) ).right, lessThanOrEqualTo( 420 + 1 ) );
      expect( docs.lastRequested, isNull, reason: 'nothing fetched: the abstract was already here' );
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

  /// 🔴 P0 e5cc78ee — Rick 2026-09-23, on the emulator: with the DM editor open in
  /// Lupin Focus (spoken, then edited with the keyboard up), neither Send nor X did
  /// anything while the rest of the screen still worked.
  ///
  /// REPRODUCED ONLY AT A REAL KEYBOARD'S HEIGHT. At 320 dp both buttons worked,
  /// which is why the first pass found nothing. At 420 dp and up (Gboard with its
  /// voice strip) the composer out-grew the body, the outer Column overflowed, and
  /// flutter_test reported the taps "would not hit test": the buttons were painted
  /// below the body's bounds. Fixed by capping the composer and scrolling it from the
  /// bottom (focus_mode_screen.dart). Mutation-proved: before the fix, every case
  /// from 380 dp up was RED, and the three cases at 420+ went "would not hit test".
  group( 'DM editor with the keyboard up — Send and X must still work', () {
    const long = 'line one of a long spoken reply\nline two\nline three\nline four\n'
                 'line five\nline six\nline seven\nline eight';

    Future<void> openEditor( WidgetTester tester, { required double keyboard } ) async {
      written( clock.subtract( const Duration( minutes: 5 ) ) );
      when( () => repo.notify( any() ) ).thenAnswer( ( _ ) async =>
          NotifyDispatchResponse.fromJson( { 'status': 'queued', 'target_user': 'cc', 'connection_count': 1 } ) );
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => long );
      await pumpScreen( tester, screen: const Size( 360, 800 ) );

      await tester.tap( railBadge( _written ) );
      await settle( tester );
      await tester.tap( byKey( TestKeys.voiceReplyMic ) );
      await settle( tester );
      await tester.tap( byKey( TestKeys.voiceReplyMic ) );
      await settle( tester );
      expect( byKey( TestKeys.voiceReplyTranscript ), findsOneWidget, reason: 'setup: editor open' );

      tester.view.viewInsets = FakeViewPadding( bottom: keyboard );
      await settle( tester );
    }

    // 0 and 320 passed before the fix; 380 and up are the ones Rick hit.
    for ( final keyboard in <double>[ 0, 320, 380, 420, 460, 500 ] ) {
      testWidgets( 'Send dispatches (keyboard ${keyboard.toInt()} dp)', ( tester ) async {
        await openEditor( tester, keyboard: keyboard );
        await tester.tap( byKey( TestKeys.voiceReplySend ) );
        await settle( tester );
        verify( () => repo.notify( any() ) ).called( 1 );
        expect( byKey( TestKeys.voiceReplyTranscript ), findsNothing, reason: 'editor closes after send' );
      } );

      testWidgets( 'X closes the editor (keyboard ${keyboard.toInt()} dp)', ( tester ) async {
        await openEditor( tester, keyboard: keyboard );
        await tester.tap( byKey( TestKeys.voiceReplyCancel ) );
        await settle( tester );
        expect( byKey( TestKeys.voiceReplyTranscript ), findsNothing );
        verifyNever( () => repo.notify( any() ) );
      } );
    }
  } );

  /// Rows 3f2a7dab + 8cc964ec (Rick 2026-09-26): the record button sat
  /// bottom-centre, on the fold of his phone. It now sits in the lower-right
  /// corner, in reach of the right thumb, with a new edit button beside it
  /// that opens the editor for typing.
  group( 'composer: record in the lower-right corner, edit beside it', () {
    for ( final screen in const [ Size( 360, 800 ), Size( 840, 900 ) ] ) {
      testWidgets( 'mic in the lower-right at ${screen.width.toInt()} dp, edit just left of it', ( tester ) async {
        written( clock.subtract( const Duration( minutes: 5 ) ) );
        await pumpScreen( tester, screen: screen );
        await tester.tap( railBadge( _written ) );
        await settle( tester );

        final mic  = tester.getRect( byKey( TestKeys.voiceReplyMic ) );
        final edit = tester.getRect( byKey( TestKeys.voiceReplyEdit ) );
        expect( mic.right, greaterThan( screen.width - 24 ),
            reason: 'hugs the right edge, not the fold at ${screen.width / 2}' );
        expect( mic.bottom, greaterThan( screen.height - 24 ), reason: 'on the bottom row' );
        expect( edit.right, lessThanOrEqualTo( mic.left + 0.5 ), reason: 'edit sits LEFT of the mic' );
        expect( edit.center.dy, closeTo( mic.center.dy, 0.5 ), reason: 'same row' );
        expect( tester.takeException(), isNull, reason: 'no overflow' );
      } );
    }

    testWidgets( 'while recording, STOP sits exactly where the mic was', ( tester ) async {
      written( clock.subtract( const Duration( minutes: 5 ) ) );
      await pumpScreen( tester, screen: const Size( 360, 800 ) );
      await tester.tap( railBadge( _written ) );
      await settle( tester );
      final before = tester.getRect( byKey( TestKeys.voiceReplyMic ) );
      await tester.tap( byKey( TestKeys.voiceReplyMic ) );
      await settle( tester );
      expect( find.byIcon( Icons.stop_circle ), findsOneWidget );
      expect( tester.getRect( byKey( TestKeys.voiceReplyMic ) ).right, closeTo( before.right, 0.5 ) );
      await tester.tap( byKey( TestKeys.voiceReplyCancel ) );
      await settle( tester );
    } );

    for ( final keyboard in <double>[ 0, 420, 500 ] ) {
      testWidgets( 'edit → type → Send dispatches the typed text (keyboard ${keyboard.toInt()} dp)', ( tester ) async {
        written( clock.subtract( const Duration( minutes: 5 ) ) );
        when( () => repo.notify( any() ) ).thenAnswer( ( _ ) async =>
            NotifyDispatchResponse.fromJson( { 'status': 'queued', 'target_user': 'cc', 'connection_count': 1 } ) );
        await pumpScreen( tester, screen: const Size( 360, 800 ) );
        await tester.tap( railBadge( _written ) );
        await settle( tester );

        await tester.tap( byKey( TestKeys.voiceReplyEdit ) );
        await settle( tester );
        tester.view.viewInsets = FakeViewPadding( bottom: keyboard );
        await settle( tester );
        await tester.enterText( byKey( TestKeys.voiceReplyTranscript ), 'typed, not spoken' );
        await tester.tap( byKey( TestKeys.voiceReplySend ) );
        await settle( tester );

        final sent = verify( () => repo.notify( captureAny() ) ).captured.single as NotifyRequest;
        expect( sent.message, 'typed, not spoken' );
        verifyNever( () => asr.startRecording() );
        expect( byKey( TestKeys.voiceReplyTranscript ), findsNothing, reason: 'editor closes after send' );
      } );
    }
  } );

  /// Row 0534b50d (parity with web row 47759aa3): a toolbar button opens the
  /// file viewer on every root, without digging up an old doc link.
  group( 'Files button: the roots landing', () {
    testWidgets( 'opens in the split, every live scope listed, roots unfolded', ( tester ) async {
      docs.scopes = const [
        DocScope( name: 'lupin',        allowedPrefixes: [ 'src/rnd/', 'io/' ] ),
        DocScope( name: 'lupin-mobile', allowedPrefixes: [] ),
        DocScope( name: 'cosa',         allowedPrefixes: [ '*' ] ),
      ];
      written( clock.subtract( const Duration( minutes: 5 ) ) );
      await pumpScreen( tester, screen: const Size( 412, 915 ) );

      expect( byKey( TestKeys.docPanel ), findsNothing );
      await tester.tap( byKey( TestKeys.focusFilesButton ) );
      await settle( tester );

      expect( byKey( TestKeys.docPanel ), findsOneWidget, reason: 'opens in the split, like a doc link' );
      expect( docs.lastRequested?.kind, DocLinkKind.io, reason: 'lands on the io listing, where Upload lives' );
      // Every root the registry returned, plus io — no tap on the panel needed.
      for ( final root in [ 'io', 'lupin/src/rnd', 'lupin/io', 'lupin-mobile', 'cosa' ] ) {
        expect( byKey( '${TestKeys.docRootPrefix}$root' ), findsOneWidget, reason: 'root $root missing' );
      }
    } );
  } );
}
