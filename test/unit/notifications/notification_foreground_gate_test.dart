/// The FOREGROUND half of row 7cac3a17 — Rick, 2026-09-28: "I'm getting
/// bombarded."
///
/// A priority switched off for the foreground stays QUIET: no ding, no spoken
/// summary. It is not dropped. `_refreshCurrent` still runs, so the item lands
/// in the list and nothing is marked played — the same rule the background wake
/// path follows. Suppression is silence, never deletion.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_delivery_policy.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

import '../_helpers/stub_dio.dart';

class _MockAudioService extends Mock implements NotificationAudioService {}
class _MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

NotificationItem _item( { required String priority } ) => NotificationItem(
  id                     : 'n-1',
  message                : 'body',
  title                  : 'title',
  type                   : 'task',
  priority               : priority,
  timestamp              : DateTime( 2026, 9, 28 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : false,
  suppressDing           : false,
  displayQualifierWidget : false,
  raw                    : const {},
);

void main() {
  late StubAdapter            adapter;
  late NotificationRepository repo;
  late _MockAudioService      audio;
  late _MockTtsOrchestrator   tts;

  void expectDinged( { required bool did } ) {
    final matcher = did ? verify : verifyNever;
    matcher( () => audio.handleIncoming(
      priority       : any( named: 'priority' ),
      message        : any( named: 'message' ),
      title          : any( named: 'title' ),
      suppressDing   : any( named: 'suppressDing' ),
      notificationId : any( named: 'notificationId' ),
      senderId       : any( named: 'senderId' ),
    ) );
  }

  void expectSpoke( { required bool did } ) {
    final matcher = did ? verify : verifyNever;
    matcher( () => tts.enqueueIfSpeakable(
      priority : any( named: 'priority' ),
      message  : any( named: 'message' ),
      title    : any( named: 'title' ),
      voiceId  : any( named: 'voiceId' ),
      sender   : any( named: 'sender' ),
    ) );
  }

  Future<NotificationDeliveryPolicy> policyWith( Map<String, Object> seed ) async {
    SharedPreferences.setMockInitialValues( seed );
    return NotificationDeliveryPolicy(
        NotificationPreferences( await SharedPreferences.getInstance() ) );
  }

  /// Drive one notification through the bloc and let the async handler settle.
  Future<void> deliver( NotificationBloc bloc, String priority ) async {
    bloc.add( NotificationsExternalUpdate( notification: _item( priority: priority ) ) );
    await Future.delayed( const Duration( milliseconds: 50 ) );
  }

  /// Load the inbox first. `_refreshCurrent` returns early while
  /// `_activeUserEmail` is null, so without this the refresh cannot be
  /// observed at all and a test asserting it would pass for the wrong reason.
  Future<void> loadInbox( NotificationBloc bloc ) async {
    bloc.add( const NotificationsLoadInbox( userEmail: 'rick@test.com' ) );
    await Future.delayed( const Duration( milliseconds: 50 ) );
  }

  setUp( () {
    // The refresh only fires while the state is NotificationsInboxLoaded, so
    // the senders call has to succeed or the assertion below would be measuring
    // a 404, not the gate.
    adapter = StubAdapter( {
      'GET /api/notifications/senders-visible/rick%40test.com': ( _ ) => jsonBody( [] ),
    } );
    repo    = NotificationRepository( makeDio( adapter ) );
    audio   = _MockAudioService();
    tts     = _MockTtsOrchestrator();
    when( () => audio.handleIncoming(
      priority       : any( named: 'priority' ),
      message        : any( named: 'message' ),
      title          : any( named: 'title' ),
      suppressDing   : any( named: 'suppressDing' ),
      notificationId : any( named: 'notificationId' ),
      senderId       : any( named: 'senderId' ),
    ) ).thenAnswer( ( _ ) async {} );
    when( () => tts.enqueueIfSpeakable(
      priority : any( named: 'priority' ),
      message  : any( named: 'message' ),
      title    : any( named: 'title' ),
      voiceId  : any( named: 'voiceId' ),
      sender   : any( named: 'sender' ),
    ) ).thenReturn( null );
  } );

  group( 'foreground gate — a switched-off priority is silent', () {
    test( 'the ding and the speech are both suppressed', () async {
      final policy = await policyWith( {
        NotificationPreferences.priorityKey( 'foreground', 'high' ): false,
      } );
      final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );

      await deliver( bloc, 'high' );

      expectDinged( did: false );
      expectSpoke( did: false );
      await bloc.close();
    } );

    test( 'a priority that is still ON is untouched by its neighbour being off', () async {
      final policy = await policyWith( {
        NotificationPreferences.priorityKey( 'foreground', 'high' ): false,
      } );
      final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );

      await deliver( bloc, 'urgent' );

      expectDinged( did: true );
      expectSpoke( did: true );
      await bloc.close();
    } );

    test( 'the master switch silences every priority', () async {
      final policy = await policyWith( { NotificationPreferences.keyEnabled: false } );
      final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );

      for ( final priority in NotificationPreferences.priorities ) {
        await deliver( bloc, priority );
      }

      expectDinged( did: false );
      expectSpoke( did: false );
      await bloc.close();
    } );

    test( 'the FOREGROUND switch silences the foreground without consulting background settings', () async {
      final policy = await policyWith( {
        NotificationPreferences.keyForegroundEnabled : false,
        NotificationPreferences.keyBackgroundEnabled : true,
      } );
      final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );

      await deliver( bloc, 'urgent' );

      expectDinged( did: false );
      expectSpoke( did: false );
      await bloc.close();
    } );
  } );

  group( 'foreground gate — what it must NOT do', () {
    test( 'a suppressed notification still reaches the list — silence, not deletion', () async {
      final policy = await policyWith( {
        NotificationPreferences.priorityKey( 'foreground', 'high' ): false,
      } );
      final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );

      // `_onExternalUpdate` ends in `_refreshCurrent`, which re-reads the
      // inbox. A gate that short-circuited the whole handler would skip that
      // and the item would silently never appear at all.
      await loadInbox( bloc );
      final afterLoad = adapter.captured.length;
      await deliver( bloc, 'high' );

      expect( adapter.captured.length, greaterThan( afterLoad ),
              reason: 'the inbox refresh must still fire for a suppressed item — '
                      'Rick asked to stop being bombarded, not to stop being told' );
      expectDinged( did: false );
      expectSpoke( did: false );
      await bloc.close();
    } );

    test( 'a suppressed notification is never marked played by this path', () async {
      final policy = await policyWith( {
        NotificationPreferences.priorityKey( 'foreground', 'high' ): false,
      } );
      final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );

      await loadInbox( bloc );
      await deliver( bloc, 'high' );

      expect(
        adapter.captured.where( ( r ) => r.path.contains( '/played' ) ),
        isEmpty,
        reason: 'suppression must not consume the item server-side',
      );
      await bloc.close();
    } );
  } );

  group( 'foreground gate — defaults and absence', () {
    test( 'with NO policy wired, everything is raised — the behaviour before this existed', () async {
      final bloc = NotificationBloc( repo, audio: audio, tts: tts );

      await deliver( bloc, 'high' );

      expectDinged( did: true );
      expectSpoke( did: true );
      await bloc.close();
    } );

    test( 'a default install raises medium, high and urgent but stays quiet on low', () async {
      final policy = await policyWith( {} );

      for ( final priority in [ 'medium', 'high', 'urgent' ] ) {
        final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );
        await deliver( bloc, priority );
        expectDinged( did: true );
        expectSpoke( did: true );
        await bloc.close();
      }

      final bloc = NotificationBloc( repo, audio: audio, tts: tts, policy: policy );
      await deliver( bloc, 'low' );
      expectDinged( did: false );
      expectSpoke( did: false );
      await bloc.close();
    } );
  } );

  /// Wire-contract grounding, same pattern as the dispatch test's cosa probe:
  /// the four checkboxes this feature offers must be the four priorities the
  /// server actually validates. A fifth tier added server-side and not here
  /// would arrive as a priority with no checkbox behind it.
  test( 'the priority set matches the server\'s valid_priorities', () {
    final cosaRoot = _findCosaRoot();
    if ( cosaRoot == null ) {
      markTestSkipped( 'needs the cosa source to ground the priority contract; '
                       'searched ../cosa and ../lupin/src/cosa at every ancestor '
                       'of ${Directory.current.path}' );
      return;
    }
    final source = File( '$cosaRoot/rest/routers/notifications.py' ).readAsStringSync();
    final match  = RegExp( r'valid_priorities\s*=\s*\[([^\]]*)\]' ).firstMatch( source );
    expect( match, isNotNull, reason: 'the server no longer declares valid_priorities '
                                      'the way this test reads it' );
    final serverSet = RegExp( r'"([a-z]+)"' )
        .allMatches( match!.group( 1 )! )
        .map( ( m ) => m.group( 1 )! )
        .toList();
    expect( serverSet, NotificationPreferences.priorities,
            reason: 'the settings view offers one checkbox per server priority, '
                    'in the server\'s own order' );
  } );
}

String? _findCosaRoot() {
  for ( var dir = Directory.current.absolute;; dir = dir.parent ) {
    for ( final rel in const [ '../cosa', '../lupin/src/cosa' ] ) {
      final candidate = Directory( '${dir.path}/$rel' );
      if ( File( '${candidate.path}/rest/routers/notifications.py' ).existsSync() ) {
        return candidate.path;
      }
    }
    if ( dir.parent.path == dir.path ) return null;
  }
}
