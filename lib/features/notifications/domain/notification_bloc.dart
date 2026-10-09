import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import '../../../services/notification_audio/notification_audio_service.dart';
import '../../../services/notification_audio/notification_delivery_policy.dart';
import '../../../services/push/notification_sender_label.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../data/notification_models.dart';
import '../data/notification_repository.dart';
import 'notification_event.dart';
import 'notification_state.dart';

// Notification type strings of the commons event family. They must match the
// server's `valid_types` whitelist in `cosa/rest/routers/notifications.py`.
// `test/unit/notifications/notification_bloc_dispatch_test.dart` checks that.

/// Notification type for an acknowledgement of a broadcast to peer sessions.
const String kNotifTypeCommonsBroadcastAck     = "commons_broadcast_ack";

/// Notification type for a direct question received from a peer session.
const String kNotifTypeCommonsQuestionReceived = "commons_question_received";

/// Notification type for an entry in the recent-activity stream.
const String kNotifTypeCommonsActivity         = "commons_activity";

/// Inbox and conversation bloc backed by the notifications REST API.
///
/// Also reacts to WebSocket queue updates: it plays audio for ordinary
/// notifications and keeps per-session persona and speakerphone snapshots.
class NotificationBloc extends Bloc<NotificationEvent, NotificationState> {
  final NotificationRepository        _repo;
  final NotificationAudioService?     _audio;
  final TtsOrchestrator?              _tts;

  /// Foreground delivery gate for ding and speech.
  ///
  /// Null means no policy is wired, which allows everything.
  final NotificationDeliveryPolicy?   _policy;

  // Context that lets an external update refresh the view on screen.
  String? _activeUserEmail;
  String? _activeSenderId;

  // Persona per sender id. Changed by persona assigned and released events and
  // copied into every loaded state for header display. Speech does not read it.
  final Map<String, VoicePersona> _personasBySender = {};

  // Frozen copy of the persona map, so a later change cannot alter a state
  // that was already emitted.
  Map<String, VoicePersona> _personasSnapshot() =>
      Map<String, VoicePersona>.unmodifiable( _personasBySender );

  /// Read-only view of the persona map, for tests.
  ///
  /// Dispatch tests use it to check that the commons event types leave the map
  /// unchanged.
  @visibleForTesting
  Map<String, VoicePersona> get personasBySenderForTesting =>
      Map<String, VoicePersona>.unmodifiable( _personasBySender );

  // Speakerphone record per sender id. Changed by `speakerphone_changed`
  // notifications and by [NotificationsSpeakerphoneChanged], and copied into
  // every loaded state. Diagnostic only; no screen shows it.
  final Map<String, SpeakerphoneRecord> _speakerphoneBySession = {};

  // Frozen copy of the speakerphone map, like `_personasSnapshot`.
  Map<String, SpeakerphoneRecord> _speakerphoneSnapshot() =>
      Map<String, SpeakerphoneRecord>.unmodifiable( _speakerphoneBySession );

  /// Read-only view of the speakerphone map, for tests.
  ///
  /// Dispatch tests use it to check how `speakerphone_changed` changes the map.
  @visibleForTesting
  Map<String, SpeakerphoneRecord> get speakerphoneBySessionForTesting =>
      Map<String, SpeakerphoneRecord>.unmodifiable( _speakerphoneBySession );

  /// Creates the bloc; [audio], [tts] and [policy] are optional collaborators.
  NotificationBloc(
    this._repo, {
    NotificationAudioService?   audio,
    TtsOrchestrator?            tts,
    NotificationDeliveryPolicy? policy,
  } ) : _audio  = audio,
        _tts    = tts,
        _policy = policy,
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
    on<NotificationsSpeakerphoneChanged>( _onSpeakerphoneChanged );
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
        senders               : senders,
        userEmail             : event.userEmail,
        personasBySender      : _personasSnapshot(),
        speakerphoneBySession : _speakerphoneSnapshot(),
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
        senderId              : event.senderId,
        userEmail             : event.userEmail,
        messages              : messages,
        personasBySender      : _personasSnapshot(),
        speakerphoneBySession : _speakerphoneSnapshot(),
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
      // Refresh the current view so badges update.
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
      // Best-effort: the backend already marks it played, and repeating is harmless.
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
    // The real event type is in `notification.type`; route on it.
    final n = event.notification;
    if ( n != null ) {
      switch ( n.type ) {
        case "task":
        case "progress":
        case "alert":
        case "custom":
        case "user_initiated_message":
        case "session_topic":
          // Ordinary user-facing notification: ding through
          // NotificationAudioService, speech through TtsOrchestrator. Both also
          // filter by priority and preferences; the gate below is the coarser one.
          //
          // When the foreground gate switches this priority off, the phone stays
          // quiet but the item is not dropped. `_refreshCurrent` below still runs,
          // so it lands in the list and nothing is marked played.
          final mayRaise = _policy?.allows(
                surface   : NotificationSurface.foreground,
                priority  : n.priority,
                senderKey : notificationSenderKey( n.raw ),
              ) ?? true;
          if ( mayRaise ) {
            _audio?.handleIncoming(
              priority     : n.priority,
              message      : n.message,
              // The title is the sender label. The background wake path builds its
              // label with the same function, so one sender reads the same in both.
              title        : notificationSenderLabel( n.raw ),
              suppressDing : n.suppressDing,
              // A tap on the foreground ding opens the same conversation as a tap
              // on a background wake notification.
              notificationId : n.id,
              senderId       : n.senderId,
            );
            _tts?.enqueueIfSpeakable(
              priority : n.priority,
              message  : n.message,
              title    : n.title,
              voiceId  : n.voicePersona?.voiceId,
              sender   : TtsSender( senderId: n.senderId, name: n.voicePersona?.displayName ?? n.voicePersona?.name, icon: n.voicePersona?.icon ),
            );
          } else {
            // ignore: avoid_print - console trace so a skipped foreground item shows in logcat
            print( "[NotificationBloc] foreground ${n.priority} is switched off "
                   "— staying quiet; the item still lands in the list (id=${n.id})" );
          }
          break;
        case "voice_persona_assigned":
          // The server allocated a persona for this sender. Update the map; the
          // refresh below copies it into the next loaded state.
          final persona = n.voicePersona;
          final sid     = n.senderId;
          if ( persona != null && sid != null ) {
            _personasBySender[ sid ] = persona;
          }
          break;
        case "voice_persona_released":
          // The server released the persona when the session ended. Drop the
          // entry so the header shows no badge; removing a missing key is a no-op.
          final sid = n.senderId;
          if ( sid != null ) _personasBySender.remove( sid );
          break;
        case "speakerphone_changed":
          // Records the session's speakerphone state and nothing else: no screen
          // and no audio routing use it. `displaced` and `displaced_by` are
          // stored as received. `NotificationItem` has no typed accessor for
          // them, so they are read from `n.raw`.
          final sid = n.senderId;
          if ( sid != null ) {
            final on        = n.raw[ "on" ] == true;
            final dispV     = n.raw[ "displaced"    ];
            final dispByV   = n.raw[ "displaced_by" ];
            _speakerphoneBySession[ sid ] = SpeakerphoneRecord(
              on          : on,
              displaced   : dispV   is String ? dispV   : null,
              displacedBy : dispByV is String ? dispByV : null,
            );
          }
          break;
        case kNotifTypeCommonsBroadcastAck:
          // No-op: acknowledgement of a peer broadcast; the app has no screen for it.
          break;
        case kNotifTypeCommonsQuestionReceived:
          // No-op: direct question for peer sessions; the app is not a peer session.
          break;
        case kNotifTypeCommonsActivity:
          // No-op: recent-activity stream; the app has no panel to fill.
          break;
        default:
          // Unknown type: log it so the gap is visible instead of dropping it
          // silently. New types get a case above this default. The old name
          // `conversation_mode_changed` has no case; `speakerphone_changed`
          // replaced it.
          // ignore: avoid_print - console trace so an unknown type shows in logcat
          print( "[NotificationBloc] Unknown notification.type: '${n.type}' (id=${n.id})" );
          break;
      }
    }
    await _refreshCurrent( emit );
  }

  // Handles [NotificationsVoicePersonaAssigned]. The WebSocket path makes the
  // same map change inside `_onExternalUpdate`.
  Future<void> _onVoicePersonaAssigned(
    NotificationsVoicePersonaAssigned event,
    Emitter<NotificationState> emit,
  ) async {
    _personasBySender[ event.senderId ] = event.persona;
    _emitCurrentSnapshot( emit );
  }

  // Handles [NotificationsVoicePersonaReleased]; a sender with no persona emits
  // nothing.
  Future<void> _onVoicePersonaReleased(
    NotificationsVoicePersonaReleased event,
    Emitter<NotificationState> emit,
  ) async {
    if ( !_personasBySender.containsKey( event.senderId ) ) return;
    _personasBySender.remove( event.senderId );
    _emitCurrentSnapshot( emit );
  }

  // Handles [NotificationsSpeakerphoneChanged]. The record has no displaced
  // fields; the WebSocket path fills them from the raw payload.
  Future<void> _onSpeakerphoneChanged(
    NotificationsSpeakerphoneChanged event,
    Emitter<NotificationState> emit,
  ) async {
    _speakerphoneBySession[ event.senderId ] = SpeakerphoneRecord(
      on : event.on,
    );
    _emitCurrentSnapshot( emit );
  }

  // Re-emits the current loaded state with fresh persona and speakerphone
  // snapshots and no refetch. States without snapshots (initial, loading, error,
  // responding, gist) are skipped; the next loaded state picks the maps up.
  void _emitCurrentSnapshot( Emitter<NotificationState> emit ) {
    final s        = state;
    final snap     = _personasSnapshot();
    final sphSnap  = _speakerphoneSnapshot();
    if ( s is NotificationsInboxLoaded ) {
      emit( NotificationsInboxLoaded(
        senders               : s.senders,
        userEmail             : s.userEmail,
        personasBySender      : snap,
        speakerphoneBySession : sphSnap,
      ) );
    } else if ( s is NotificationsConversationLoaded ) {
      emit( NotificationsConversationLoaded(
        senderId              : s.senderId,
        userEmail             : s.userEmail,
        messages              : s.messages,
        personasBySender      : snap,
        speakerphoneBySession : sphSnap,
      ) );
    } else if ( s is NotificationsSenderDatesLoaded ) {
      emit( NotificationsSenderDatesLoaded(
        senderId              : s.senderId,
        userEmail             : s.userEmail,
        dates                 : s.dates,
        personasBySender      : snap,
        speakerphoneBySession : sphSnap,
      ) );
    } else if ( s is NotificationsConversationByDateLoaded ) {
      emit( NotificationsConversationByDateLoaded(
        senderId              : s.senderId,
        userEmail             : s.userEmail,
        byDate                : s.byDate,
        personasBySender      : snap,
        speakerphoneBySession : sphSnap,
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
      // Restore the conversation so the list stays visible after the sheet closes.
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
        senderId              : event.senderId,
        userEmail             : event.userEmail,
        dates                 : dates,
        personasBySender      : _personasSnapshot(),
        speakerphoneBySession : _speakerphoneSnapshot(),
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
        senderId              : event.senderId,
        userEmail             : event.userEmail,
        byDate                : byDate,
        personasBySender      : _personasSnapshot(),
        speakerphoneBySession : _speakerphoneSnapshot(),
      ) );
    } on NotificationApiException catch ( e ) {
      emit( NotificationsError( e.message ) );
    }
  }

  // Refetches the current view (inbox, conversation or by-date) and emits it.
  // Does nothing before a view has been loaded; keeps the last good state if the
  // refetch fails.
  Future<void> _refreshCurrent( Emitter<NotificationState> emit ) async {
    if ( _activeUserEmail == null ) return;
    try {
      if ( _activeSenderId != null && state is NotificationsConversationLoaded ) {
        final msgs = await _repo.conversation(
          _activeSenderId!,
          _activeUserEmail!,
        );
        emit( NotificationsConversationLoaded(
          senderId              : _activeSenderId!,
          userEmail             : _activeUserEmail!,
          messages              : msgs,
          personasBySender      : _personasSnapshot(),
          speakerphoneBySession : _speakerphoneSnapshot(),
        ) );
      } else if ( _activeSenderId != null && state is NotificationsConversationByDateLoaded ) {
        final byDate = await _repo.conversationByDate(
          _activeSenderId!,
          _activeUserEmail!,
        );
        emit( NotificationsConversationByDateLoaded(
          senderId              : _activeSenderId!,
          userEmail             : _activeUserEmail!,
          byDate                : byDate,
          personasBySender      : _personasSnapshot(),
          speakerphoneBySession : _speakerphoneSnapshot(),
        ) );
      } else if ( state is NotificationsInboxLoaded ) {
        final senders = await _repo.sendersVisible( _activeUserEmail! );
        emit( NotificationsInboxLoaded(
          senders               : senders,
          userEmail             : _activeUserEmail!,
          personasBySender      : _personasSnapshot(),
          speakerphoneBySession : _speakerphoneSnapshot(),
        ) );
      }
    } on NotificationApiException catch ( _ ) {
      // Best-effort refresh: keep the last good state.
    }
  }
}
