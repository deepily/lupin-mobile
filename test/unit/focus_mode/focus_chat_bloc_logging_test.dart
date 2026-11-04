// FocusChatBloc failure paths log through the app Logger under the FocusChat tag.
// Server detail text and parse errors can quote stored content, and the user's email must stay out of every entry.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}

class _Capture implements LogDestination {
  final List<LogEntry> entries = [];

  @override
  void write( LogEntry entry ) => entries.add( entry );

  @override
  Future<void> flush() async {}
}

const _email  = 'rick-private@example.com';
const _secret = 'SECRET-DETAIL-TEXT';

NotificationItem _item( String id, String? sender, { bool ask = false } ) => NotificationItem(
  id                     : id,
  message                : 'msg-$id',
  type                   : 'task',
  priority               : 'medium',
  senderId               : sender,
  timestamp              : DateTime( 2026, 6, 12, 1 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : ask,
  responseType           : ask ? 'yes_no' : null,
  suppressDing           : false,
  displayQualifierWidget : false,
);

void main() {
  late _MockRepo repo;
  late _Capture  capture;
  late FocusChatBloc bloc;

  Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 20 ) );

  void stubSendersOk() {
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async => [ SenderSummary( senderId: 'S@x#1', lastActivity: DateTime( 2026, 6, 12 ), count: 1 ) ] );
    when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => const [] );
  }

  Future<void> coldStart() async {
    bloc.add( const FocusColdStartRequested( userEmail: _email ) );
    await pump();
    capture.entries.clear();
  }

  Iterable<LogEntry> focusEntries() => capture.entries.where( ( e ) => e.tag == 'FocusChat' );

  /// The one entry a failure must produce, checked for level, message, stack and secrecy.
  LogEntry single( LogLevel level, String message ) {
    final found = focusEntries().toList();
    expect( found, hasLength( 1 ), reason: found.map( ( e ) => e.message ).join( ' | ' ) );
    expect( found.single.level, level );
    expect( found.single.message, message );
    final everything = jsonEncode( capture.entries.map( ( e ) => e.toJson() ).toList() );
    expect( everything, isNot( contains( _secret ) ) );
    expect( everything, isNot( contains( _email ) ) );
    expect( everything, isNot( contains( '[FocusChat]' ) ), reason: 'the tag is a field, not a message prefix' );
    return found.single;
  }

  setUpAll( () {
    registerFallbackValue( const NotificationResponsePayload( notificationId: 'f', responseValue: 'f' ) );
    registerFallbackValue( const NotifyRequest( message: 'f', targetUser: 'f' ) );
  } );

  setUp( () {
    Logger.resetForTesting();
    capture = _Capture();
    Logger.addDestination( capture );
    repo = _MockRepo();
    bloc = FocusChatBloc( repo, tts: _MockTts() );
  } );

  tearDown( () async {
    await bloc.close();
    Logger.resetForTesting();
  } );

  test( 'an inbound without a sender id is a warning with the notification id', () async {
    bloc.add( FocusInboundNotification( _item( 'n-1', null ) ) );
    await pump();

    final e = single( LogLevel.warning, 'Inbound notification without a sender id dropped' );
    expect( e.context!.metadata, { 'notificationId': 'n-1' } );
  } );

  test( 'a failed backfill is an error with the sender, the status and a stack; the server detail stays out', () async {
    stubSendersOk();
    await coldStart();
    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ), anchor: any( named: 'anchor' ) ) )
        .thenThrow( const NotificationApiException( _secret, statusCode: 502 ) );

    bloc.add( const FocusSenderSelected( 'S@x#1' ) );
    await pump();

    final e = single( LogLevel.error, 'Conversation backfill failed' );
    expect( e.error, 'NotificationApiException' );
    expect( e.stackTrace, isNotNull );
    expect( e.context!.metadata, { 'senderId': 'S@x#1', 'statusCode': 502 } );
  } );

  test( 'an unavailable live-seat roster is a warning; a parse error does not quote its text', () async {
    stubSendersOk();
    when( () => repo.activeSessions() ).thenThrow( const FormatException( _secret ) );

    bloc.add( const FocusColdStartRequested( userEmail: _email ) );
    await pump();

    final e = single( LogLevel.warning, 'Live-seat roster unavailable' );
    expect( e.error, startsWith( 'FormatException' ) );
    expect( e.stackTrace, isNotNull );
  } );

  test( 'a failed cold start is an error with the status', () async {
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
        .thenThrow( const NotificationApiException( _secret, statusCode: 500 ) );
    when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => const [] );

    bloc.add( const FocusColdStartRequested( userEmail: _email ) );
    await pump();

    final e = single( LogLevel.error, 'Cold start failed' );
    expect( e.context!.metadata, { 'statusCode': 500 } );
    expect( e.stackTrace, isNotNull );
  } );

  test( 'a failed reconnect refresh is an error with the status', () async {
    stubSendersOk();
    await coldStart();
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
        .thenThrow( const NotificationApiException( _secret, statusCode: 503 ) );

    bloc.add( const FocusRosterRefreshRequested() );
    await pump();

    final e = single( LogLevel.error, 'Reconnect refresh failed' );
    expect( e.context!.metadata, { 'statusCode': 503 } );
    expect( e.stackTrace, isNotNull );
  } );

  test( 'a failed response to an ask is an error with the sender and the ask id', () async {
    stubSendersOk();
    await coldStart();
    bloc.add( FocusInboundNotification( _item( 'ask-1', 'S@x#1', ask: true ) ) );
    await pump();
    capture.entries.clear();
    when( () => repo.respond( any() ) ).thenThrow( const NotificationApiException( _secret, statusCode: 500 ) );

    bloc.add( const FocusRespondRequested( senderId: 'S@x#1', text: 'yes' ) );
    await pump();

    final e = single( LogLevel.error, 'Response to an ask failed' );
    expect( e.context!.metadata, { 'senderId': 'S@x#1', 'notificationId': 'ask-1', 'statusCode': 500 } );
    expect( e.stackTrace, isNotNull );
  } );

  test( 'an address that cannot take a direct message is a warning; the user email is in neither message nor metadata', () async {
    stubSendersOk();
    await coldStart();

    bloc.add( const FocusRespondRequested( senderId: 'plain-sender', text: 'yo' ) );
    await pump();

    final e = single( LogLevel.warning, 'Cannot address a direct message to this sender' );
    expect( e.context!.metadata, { 'senderId': 'plain-sender', 'hasUserEmail': true } );
  } );

  test( 'the user email as a sender id is logged as a placeholder, in any case and with stray spaces', () async {
    stubSendersOk();
    await coldStart();

    for ( final spelling in [ _email, _email.toUpperCase(), '  $_email', '$_email  ' ] ) {
      capture.entries.clear();
      bloc.add( FocusRespondRequested( senderId: spelling, text: 'yo' ) );
      await pump();

      final found = focusEntries().toList();
      expect( found, hasLength( 1 ), reason: spelling );
      expect( found.single.context!.metadata![ 'senderId' ], '<user>', reason: spelling );
      expect( jsonEncode( found.single.toJson() ).toLowerCase(), isNot( contains( _email ) ), reason: spelling );
    }
  } );

  test( 'a failed direct message is an error with the sender and the status', () async {
    stubSendersOk();
    await coldStart();
    when( () => repo.notify( any() ) ).thenThrow( const NotificationApiException( _secret, statusCode: 401 ) );

    bloc.add( const FocusRespondRequested( senderId: 'S@x#1', text: 'hello?' ) );
    await pump();

    final e = single( LogLevel.error, 'Direct message failed' );
    expect( e.context!.metadata, { 'senderId': 'S@x#1', 'statusCode': 401 } );
    expect( e.stackTrace, isNotNull );
  } );
}
