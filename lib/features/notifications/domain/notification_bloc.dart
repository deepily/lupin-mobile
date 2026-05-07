import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/notification_audio/notification_audio_service.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../data/notification_models.dart';
import '../data/notification_repository.dart';
import 'notification_event.dart';
import 'notification_state.dart';

/// Repository-backed inbox + conversation BLoC. Replaces the prior
/// websocket-only skeleton with real REST integration against the
/// 17-endpoint notifications API.
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository        _repo;
  final NotificationAudioService?     _audio;
  final TtsOrchestrator?              _tts;

  // Track context so external updates can refresh the right view.
  String? _activeUserEmail;
  String? _activeSenderId;

  NotificationBloc(
    this._repo, {
    NotificationAudioService? audio,
    TtsOrchestrator?          tts,
  } ) : _audio = audio,
        _tts   = tts,
        super( const NotificationsInitial() ) {
    on<NotificationsLoadInbox>( _onLoadInbox );
    on<NotificationsLoadConversation>( _onLoadConversation );
    on<NotificationsMarkPlayed>( _onMarkPlayed );
    on<NotificationsRespond>( _onRespond );
    on<NotificationsBulkDelete>( _onBulkDelete );
    on<NotificationsDeleteConversation>( _onDeleteConversation );
    on<NotificationsExternalUpdate>( _onExternalUpdate );
    on<NotificationsGenerateGistRequested>( _onGenerateGist );
    on<NotificationsLoadSenderDates>( _onLoadSenderDates );
    on<NotificationsLoadConversationByDate>( _onLoadConversationByDate );
  }

  Future<void> _onLoadInbox(
    NotificationsLoadInbox event,
    Emitter<NotificationState> emit,
  ) async {
    _activeUserEmail = event.userEmail;
    emit( const NotificationsLoading() );
    try {
      final senders = await _repo.sendersVisible(
        event.userEmail,
        hours          : event.hours,
        includeHidden  : event.includeHidden,
        excludeOwnJobs : event.excludeOwnJobs,
      );
      emit( NotificationsInboxLoaded(
        senders   : senders,
        userEmail : event.userEmail,
      ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onLoadConversation(
    NotificationsLoadConversation event,
    Emitter<NotificationState> emit,
  ) async {
    _activeUserEmail = event.userEmail;
    _activeSenderId  = event.senderId;
    emit( const NotificationsLoading() );
    try {
      final messages = await _repo.conversation(
        event.senderId,
        event.userEmail,
        hours: event.hours,
      );
      emit( NotificationsConversationLoaded(
        senderId  : event.senderId,
        userEmail : event.userEmail,
        messages  : messages,
      ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onMarkPlayed(
    NotificationsMarkPlayed event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      await _repo.markPlayed( event.notificationId );
      // Re-emit current view so badges update.
      _refreshCurrent( emit );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onRespond(
    NotificationsRespond event,
    Emitter<NotificationState> emit,
  ) async {
    emit( NotificationsResponding( event.notificationId ) );
    try {
      final ack = await _repo.respond( NotificationResponsePayload(
        notificationId : event.notificationId,
        responseValue  : event.responseValue,
      ) );
      // Best-effort mark-played; backend already does it but keep idempotent.
      try { await _repo.markPlayed( event.notificationId ); } catch ( _ ) {}
      emit( NotificationsResponseAcked( ack ) );
      await _refreshCurrent( emit );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onBulkDelete(
    NotificationsBulkDelete event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      await _repo.bulkDelete(
        event.userEmail,
        hours          : event.hours,
        excludeOwnJobs : event.excludeOwnJobs,
      );
      add( NotificationsLoadInbox( userEmail: event.userEmail ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onDeleteConversation(
    NotificationsDeleteConversation event,
    Emitter<NotificationState> emit,
  ) async {
    try {
      await _repo.deleteConversation( event.senderId, event.userEmail );
      add( NotificationsLoadInbox( userEmail: event.userEmail ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onExternalUpdate(
    NotificationsExternalUpdate event,
    Emitter<NotificationState> emit,
  ) async {
    // Inner-type discriminator pivot (Phase 0 dispatch audit, 2026-05-06).
    // Server `notification_queue_update` envelopes carry the real event in
    // `notification.type`. Future feature ports (voice-persona, conversation-mode,
    // session-switcher) add cases here without further dispatch-table edits.
    final n = event.notification;
    if ( n != null ) {
      switch ( n.type ) {
        case "task":
        case "progress":
        case "alert":
        case "custom":
        case "user_initiated_message":
        case "session_topic":
          // Ordinary user-facing notification. Ding via NotificationAudioService
          // (OS channel); speech via TtsOrchestrator (ElevenLabs → flutter_tts).
          // Both filter by priority + preferences internally; bloc doesn't gate.
          _audio?.handleIncoming(
            priority     : n.priority,
            message      : n.message,
            title        : n.title,
            suppressDing : n.suppressDing,
          );
          _tts?.enqueueIfSpeakable(
            priority : n.priority,
            message  : n.message,
            title    : n.title,
          );
          break;
        default:
          // Unknown inner type — log so the gap is visible. Silent drop is the
          // bug Phase 0 prevents. Future feature ports replace this branch with
          // explicit cases (e.g., `voice_persona_assigned`).
          // ignore: avoid_print
          print( "[NotificationBloc] Unknown notification.type: '${n.type}' (id=${n.id})" );
          break;
      }
    }
    await _refreshCurrent( emit );
  }

  Future<void> _onGenerateGist(
    NotificationsGenerateGistRequested _,
    Emitter<NotificationState> emit,
  ) async {
    final s = state;
    if ( s is! NotificationsConversationLoaded ) return;
    if ( s.messages.isEmpty ) return;
    emit( const NotificationsGistLoading() );
    try {
      final gist = await _repo.generateGist( GistRequest(
        messages  : s.messages.map( ( m ) => m.message                  ).toList(),
        abstracts : s.messages.map( ( m ) => m.abstractText ?? ""       ).toList(),
      ) );
      emit( NotificationsGistReady( gist.gist ) );
      // Restore the conversation view so the list stays visible after the sheet closes.
      emit( s );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
      emit( s );
    }
  }

  Future<void> _onLoadSenderDates(
    NotificationsLoadSenderDates event,
    Emitter<NotificationState> emit,
  ) async {
    _activeUserEmail = event.userEmail;
    _activeSenderId  = event.senderId;
    emit( const NotificationsLoading() );
    try {
      final dates = await _repo.senderDates(
        event.senderId,
        event.userEmail,
        includeHidden: event.includeHidden,
      );
      emit( NotificationsSenderDatesLoaded(
        senderId  : event.senderId,
        userEmail : event.userEmail,
        dates     : dates,
      ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  Future<void> _onLoadConversationByDate(
    NotificationsLoadConversationByDate event,
    Emitter<NotificationState> emit,
  ) async {
    _activeUserEmail = event.userEmail;
    _activeSenderId  = event.senderId;
    emit( const NotificationsLoading() );
    try {
      final byDate = await _repo.conversationByDate(
        event.senderId,
        event.userEmail,
        hours         : event.hours,
        anchor        : event.anchor,
        includeHidden : event.includeHidden,
      );
      emit( NotificationsConversationByDateLoaded(
        senderId  : event.senderId,
        userEmail : event.userEmail,
        byDate    : byDate,
      ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  /// Re-fetch the current view (inbox or conversation) without changing
  /// emit ordering. No-op if there's no tracked context yet.
  Future<void> _refreshCurrent( Emitter<NotificationState> emit ) async {
    if ( _activeUserEmail == null ) return;
    try {
      if ( _activeSenderId != null && state is NotificationsConversationLoaded ) {
        final msgs = await _repo.conversation(
          _activeSenderId!,
          _activeUserEmail!,
        );
        emit( NotificationsConversationLoaded(
          senderId  : _activeSenderId!,
          userEmail : _activeUserEmail!,
          messages  : msgs,
        ) );
      } else if ( _activeSenderId != null && state is NotificationsConversationByDateLoaded ) {
        final byDate = await _repo.conversationByDate(
          _activeSenderId!,
          _activeUserEmail!,
        );
        emit( NotificationsConversationByDateLoaded(
          senderId  : _activeSenderId!,
          userEmail : _activeUserEmail!,
          byDate    : byDate,
        ) );
      } else if ( state is NotificationsInboxLoaded ) {
        final senders = await _repo.sendersVisible( _activeUserEmail! );
        emit( NotificationsInboxLoaded(
          senders   : senders,
          userEmail : _activeUserEmail!,
        ) );
      }
    } on NotificationApiException catch ( _ ) {
      // Keep last good state silently — refresh is best-effort.
    }
  }
}
