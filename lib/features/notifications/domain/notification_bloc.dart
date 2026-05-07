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

  // Per-session persona snapshot keyed on senderId. Mutated from
  // `voice_persona_assigned` / `voice_persona_released` events; rendered
  // into every loaded state's `personasBySender` for header display
  // (Phase 2 of the voice-persona milestone). Per Q1, this map is for
  // header rendering only — TTS dispatch reads persona straight off the
  // originating notification.
  final Map<String, VoicePersona> _personasBySender = {};

  /// Defensive snapshot of the persona map at every emit site.
  /// `Map.unmodifiable` copies the current entries and freezes the result,
  /// so a later mutation to `_personasBySender` cannot leak into a
  /// previously-emitted state.
  Map<String, VoicePersona> _personasSnapshot() =>
      Map<String, VoicePersona>.unmodifiable( _personasBySender );

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
    on<NotificationsVoicePersonaAssigned>( _onVoicePersonaAssigned );
    on<NotificationsVoicePersonaReleased>( _onVoicePersonaReleased );
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
        senders          : senders,
        userEmail        : event.userEmail,
        personasBySender : _personasSnapshot(),
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
        senderId         : event.senderId,
        userEmail        : event.userEmail,
        messages         : messages,
        personasBySender : _personasSnapshot(),
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
        case "voice_persona_assigned":
          // Server allocated a voice persona for this senderId. Mutate the
          // persona map; the upcoming _refreshCurrent() emit will snapshot it
          // into the next loaded state. Per Q1, no separate mobile cache —
          // this map is for header rendering only.
          final persona = n.voicePersona;
          final sid     = n.senderId;
          if ( persona != null && sid != null ) {
            _personasBySender[ sid ] = persona;
          }
          break;
        case "voice_persona_released":
          // Server released the persona (SessionEnd cleared the bridge).
          // Drop the entry; future renders see no persona for this senderId
          // and fall back to no-badge behavior. Idempotent: removing a
          // missing key is a no-op.
          final sid = n.senderId;
          if ( sid != null ) _personasBySender.remove( sid );
          break;
        default:
          // Unknown inner type — log so the gap is visible. Silent drop is
          // the bug Phase 0 prevents. Future feature ports add cases above
          // this default branch (conversation_mode_changed, focus_changed,
          // etc.).
          // ignore: avoid_print
          print( "[NotificationBloc] Unknown notification.type: '${n.type}' (id=${n.id})" );
          break;
      }
    }
    await _refreshCurrent( emit );
  }

  /// Handler for the dedicated `NotificationsVoicePersonaAssigned` event.
  /// Used by tests + any future programmatic dispatcher. The WS path goes
  /// through `_onExternalUpdate` directly and shares the same map mutation,
  /// so behavior is identical regardless of entry point.
  Future<void> _onVoicePersonaAssigned(
    NotificationsVoicePersonaAssigned event,
    Emitter<NotificationState> emit,
  ) async {
    _personasBySender[ event.senderId ] = event.persona;
    _emitCurrentSnapshot( emit );
  }

  /// Handler for the dedicated `NotificationsVoicePersonaReleased` event.
  /// Idempotent: if the senderId has no current persona, the handler returns
  /// without emitting (per Phase 2 test 2.4.4 — `expect: []` for unknown
  /// release).
  Future<void> _onVoicePersonaReleased(
    NotificationsVoicePersonaReleased event,
    Emitter<NotificationState> emit,
  ) async {
    if ( !_personasBySender.containsKey( event.senderId ) ) return;
    _personasBySender.remove( event.senderId );
    _emitCurrentSnapshot( emit );
  }

  /// Re-emit the current loaded state with an updated `personasBySender`
  /// snapshot. No data refetch; only the persona map changes. States that
  /// don't carry the snapshot (Initial / Loading / Error / Responding /
  /// Gist*) are not re-emitted — the next loaded state will pick up the
  /// fresh map on its own emit path.
  void _emitCurrentSnapshot( Emitter<NotificationState> emit ) {
    final s = state;
    final snap = _personasSnapshot();
    if ( s is NotificationsInboxLoaded ) {
      emit( NotificationsInboxLoaded(
        senders          : s.senders,
        userEmail        : s.userEmail,
        personasBySender : snap,
      ) );
    } else if ( s is NotificationsConversationLoaded ) {
      emit( NotificationsConversationLoaded(
        senderId         : s.senderId,
        userEmail        : s.userEmail,
        messages         : s.messages,
        personasBySender : snap,
      ) );
    } else if ( s is NotificationsSenderDatesLoaded ) {
      emit( NotificationsSenderDatesLoaded(
        senderId         : s.senderId,
        userEmail        : s.userEmail,
        dates            : s.dates,
        personasBySender : snap,
      ) );
    } else if ( s is NotificationsConversationByDateLoaded ) {
      emit( NotificationsConversationByDateLoaded(
        senderId         : s.senderId,
        userEmail        : s.userEmail,
        byDate           : s.byDate,
        personasBySender : snap,
      ) );
    }
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
        senderId         : event.senderId,
        userEmail        : event.userEmail,
        dates            : dates,
        personasBySender : _personasSnapshot(),
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
        senderId         : event.senderId,
        userEmail        : event.userEmail,
        byDate           : byDate,
        personasBySender : _personasSnapshot(),
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
          senderId         : _activeSenderId!,
          userEmail        : _activeUserEmail!,
          messages         : msgs,
          personasBySender : _personasSnapshot(),
        ) );
      } else if ( _activeSenderId != null && state is NotificationsConversationByDateLoaded ) {
        final byDate = await _repo.conversationByDate(
          _activeSenderId!,
          _activeUserEmail!,
        );
        emit( NotificationsConversationByDateLoaded(
          senderId         : _activeSenderId!,
          userEmail        : _activeUserEmail!,
          byDate           : byDate,
          personasBySender : _personasSnapshot(),
        ) );
      } else if ( state is NotificationsInboxLoaded ) {
        final senders = await _repo.sendersVisible( _activeUserEmail! );
        emit( NotificationsInboxLoaded(
          senders          : senders,
          userEmail        : _activeUserEmail!,
          personasBySender : _personasSnapshot(),
        ) );
      }
    } on NotificationApiException catch ( _ ) {
      // Keep last good state silently — refresh is best-effort.
    }
  }
}
