import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}

NotificationItem _ask( String id, String sender, String type, Map<String, dynamic>? options ) {
  return NotificationItem(
    id                     : id,
    message                : 'msg-$id',
    type                   : 'task',
    priority               : 'medium',
    senderId               : sender,
    timestamp              : DateTime( 2026, 6, 12, 1 ),
    played                 : false,
    playCount              : 0,
    responseRequested      : true,
    responseType           : type,
    responseOptions        : options,
    suppressDing           : false,
    displayQualifierWidget : false,
  );
}

/// A typed reply to a multiple_choice ask is posted as {"answers": {header: text}}.
void main() {
  late _MockRepo repo;
  late _MockTts  tts;
  FocusChatBloc? bloc;

  setUpAll( () {
    registerFallbackValue( const NotificationResponsePayload( notificationId: 'fallback', responseValue: 'fallback' ) );
  } );

  setUp( () {
    repo = _MockRepo();
    tts  = _MockTts();
    bloc = FocusChatBloc( repo, tts: tts );
  } );

  tearDown( () async => bloc?.close() );

  Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

  Future<String> respondTo( String type, Map<String, dynamic>? options, String text ) async {
    when( () => repo.respond( any() ) ).thenAnswer( ( _ ) async =>
        NotificationResponseAck.fromJson( { 'status': 'ok', 'notification_id': 'ask-1' } ) );
    bloc!.add( FocusInboundNotification( _ask( 'ask-1', 'S', type, options ) ) );
    await pump();
    bloc!.add( FocusRespondRequested( senderId: 'S', text: text,
        promptContext: const FocusPromptContext( notificationId: 'ask-1' ) ) );
    await pump();
    final sent = verify( () => repo.respond( captureAny() ) ).captured.single as NotificationResponsePayload;
    return sent.responseValue as String;
  }

  final mcOptions = <String, dynamic>{ 'questions': [
    { 'header': 'Confirm Command', 'question': 'Run it?', 'options': [ 'Yes', 'No' ] },
  ] };

  test( 'multiple_choice + typed text → {"answers": {<header>: <text>}}', () async {
    final sent = await respondTo( 'multiple_choice', mcOptions, 'only the first file' );
    expect( jsonDecode( sent ), { 'answers': { 'Confirm Command': 'only the first file' } } );
  } );

  test( 'multiple_choice + text already wrapped by the pane → sent as is, not wrapped twice', () async {
    final wrapped = jsonEncode( { 'answers': { 'Confirm Command': 'Yes' } } );
    expect( await respondTo( 'multiple_choice', mcOptions, wrapped ), wrapped );
  } );

  test( 'multiple_choice question without a header → key q_0, as the prompt body keys it', () async {
    final sent = await respondTo( 'multiple_choice', { 'questions': [ { 'question': 'Run it?' } ] }, 'later' );
    expect( jsonDecode( sent ), { 'answers': { 'q_0': 'later' } } );
  } );

  test( 'multiple_choice with no nested questions → bare string (no header to key on)', () async {
    expect( await respondTo( 'multiple_choice', { 'options': [ 'a', 'b' ] }, 'a' ), 'a' );
  } );

  test( 'yes_no and open_ended keep the bare string', () async {
    expect( await respondTo( 'yes_no', null, 'yes' ), 'yes' );
  } );

  test( 'open_ended keeps the bare string', () async {
    expect( await respondTo( 'open_ended', null, 'free text' ), 'free text' );
  } );
}
