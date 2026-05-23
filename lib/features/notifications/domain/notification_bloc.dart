import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import '../../../services/notification_audio/notification_audio_service.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../data/notification_models.dart';
import '../data/notification_repository.dart';
import 'notification_event.dart';
import 'notification_state.dart';

// ──────────────────────────────────────────────────────────────────────────
// Section A (Phase 1) — Commons WS event-type constants
// ──────────────────────────────────────────────────────────────────────────
//
// Server-defined notification.type strings for the new commons-* WS event
// family. These constants MUST exact-match the cosa `valid_types` whitelist
// (`cosa/rest/routers/notifications.py:359-364`) AND the original emit-site
// commits (`799f4ce`, `d18cdf9`, `15599db`, `6136a88`, `fe352b8`).
//
// AC-A5 — the dispatch test in
// `test/unit/notifications/notification_bloc_dispatch_test.dart` asserts the
// wire-contract equality (mobile case-label constants ↔ cosa whitelist).
// Wire-string equality is verified, not assumed (cascade Stage-2 finding
// F-Krishna-A1, cluster-family fix).
const String kNotifTypeCommonsBroadcastAck     = "commons_broadcast_ack";
const String kNotifTypeCommonsQuestionReceived = "commons_question_received";
const String kNotifTypeCommonsActivity         = "commons_activity";

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

  /// Test-only observation of `_personasBySender` (AC-A2 / F-Krishna-A2).
  /// Used by the Section-A dispatch tests to verify the new no-op cases
  /// (`commons_broadcast_ack`, `commons_question_received`, `commons_activity`)
  /// do NOT mutate the persona map. Returns an unmodifiable view so a test
  /// caller cannot accidentally mutate bloc state.
  @visibleForTesting
  Map<String, VoicePersona> get personasBySenderForTesting =>
      Map<String, VoicePersona>.unmodifiable( _personasBySender );

  /// Per-session speakerphone state, keyed by `n.senderId`. Mutated from
  /// `speakerphone_changed` WS events (Section B / Phase 2,
  /// 2026-05-23 notif-client-sync) and from the dedicated typed event
  /// `NotificationsSpeakerphoneChanged`; rendered into every loaded state's
  /// `speakerphoneBySession` snapshot. Diagnostic only — no UI surface yet
  /// (Q1 record-only resolution, plan §8.0).
  final Map<String, SpeakerphoneRecord> _speakerphoneBySession = {};

  /// Defensive snapshot of the speakerphone map at every emit site; mirrors
  /// `_personasSnapshot()`.
  Map<String, SpeakerphoneRecord> _speakerphoneSnapshot() =>
      Map<String, SpeakerphoneRecord>.unmodifiable( _speakerphoneBySession );

  /// Test-only observation of `_speakerphoneBySession` (AC-B2–B6 — uniform
  /// observation mechanism, F-Krishna-A2 forward-sweep). Used by the
  /// Section-B dispatch tests to verify the new `speakerphone_changed`
  /// case mutates / preserves the map as specified. Returns an unmodifiable
  /// view so a test caller cannot accidentally mutate bloc state.
  @visibleForTesting
  Map<String, SpeakerphoneRecord> get speakerphoneBySessionForTesting =>
      Map<String, SpeakerphoneRecord>.unmodifiable( _speakerphoneBySession );

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
            voiceId  : n.voicePersona?.voiceId,
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
        case "speakerphone_changed":
          // Section B (Phase 2, 2026-05-23 notif-client-sync) — per-session
          // speakerphone state record-only (Q1 resolution, plan §8.0). No UI
          // surface; no TTS / audio-routing change. Diagnostic fields
          // `displaced` / `displaced_by` stored verbatim for future use, not
          // acted on (AC-B6).
          //
          // OSQ B-1 resolution: `NotificationItem` has no typed accessor for
          // these payload fields — access path is `n.raw[...]`. Wire-contract
          // grounding (type string + payload field names) verified by AC-B7
          // against cosa commit `e420ec0` (read-only — no git operations on
          // the cosa repo).
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
          // no-op stub — inter-session ack feedback for CC peer broadcasts; no mobile UI surface yet; real behavior parked per Q3 (plan §8.0)
          break;
        case kNotifTypeCommonsQuestionReceived:
          // no-op stub — DM push for CC peer sessions; mobile is not a CC peer; real behavior parked per Q3 (plan §8.0)
          break;
        case kNotifTypeCommonsActivity:
          // no-op stub — Recent Activity stream for peer-traffic surfaces; no mobile panel to populate; real behavior parked per Q3 (plan §8.0)
          break;
        default:
          // Unknown inner type — log so the gap is visible. Silent drop is
          // the bug Phase 0 prevents. Future feature ports add cases above
          // this default branch (focus_changed, etc.). The legacy name
          // `conversation_mode_changed` (superseded by `speakerphone_changed`
          // per Q2, plan §8.0) is intentionally NOT in the above future-cases
          // list — the server's Path III bridge handles non-mobile clients,
          // and mobile's smoke-test guard AC-B5 catches wire drift if the
          // legacy name ever reappears.
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

  /// Handler for the dedicated `NotificationsSpeakerphoneChanged` typed event
  /// (Section B / Phase 2). Used by tests + future programmatic dispatchers;
  /// mirrors `_onVoicePersonaAssigned`. The typed event is 2-field
  /// (senderId, on) so `displaced` / `displacedBy` are null on the resulting
  /// `SpeakerphoneRecord` — the WS path in `_onExternalUpdate` populates
  /// those diagnostic fields from raw payload.
  Future<void> _onSpeakerphoneChanged(
    NotificationsSpeakerphoneChanged event,
    Emitter<NotificationState> emit,
  ) async {
    _speakerphoneBySession[ event.senderId ] = SpeakerphoneRecord(
      on : event.on,
    );
    _emitCurrentSnapshot( emit );
  }

  /// Re-emit the current loaded state with an updated `personasBySender`
  /// snapshot. No data refetch; only the persona map changes. States that
  /// don't carry the snapshot (Initial / Loading / Error / Responding /
  /// Gist*) are not re-emitted — the next loaded state will pick up the
  /// fresh map on its own emit path.
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
      // Keep last good state silently — refresh is best-effort.
    }
  }
}
