class AppConstants {
  AppConstants._();
  
  // App Information
  static const String appName = 'Lupin Mobile';
  static const String appVersion = '1.0.0';
  
  // API Configuration
  // NOTE: These are runtime-mutable. ServerContextService rewrites them
  // when the user toggles Dev ↔ Test in settings. Defaults match Dev.
  // 10.0.2.2 is the Android emulator's host-loopback alias (maps to the
  // host's 127.0.0.1). For desktop/iOS we'd need localhost — revisit if
  // we add those targets.
  static String apiBaseUrl = 'http://10.0.2.2:7999';
  static String wsBaseUrl  = 'ws://10.0.2.2:7999';
  
  // WebSocket Endpoints
  static const String wsQueueEndpoint = '/ws/queue';
  static const String wsAudioEndpoint = '/ws/audio';
  
  // WebSocket Event Types
  // Queue Events
  //
  // 🔴 DISPOSITION (AC-S1.11, 2026-08-29): THESE FOUR ARE NEVER EMITTED BY THE
  // SERVER. They have zero emit sites in the Lupin backend and do not appear in
  // the INI's `websocket available events`; the parent repo measured this and
  // wrote the receipt into `src/tests/lupin_smoke/test_queue_workflow.py:280`.
  // The live event carrying job status is `eventJobStateTransition` below.
  //
  // KEPT rather than deleted, deliberately: they are referenced from four
  // WebSocket services that no section of the Quick Ask plan owns
  // (`websocket_message_router.dart`, `websocket_subscription_manager.dart`,
  // `websocket_dynamic_subscription_controller.dart`) plus several test
  // helpers. Removing them is a ~40-site edit reaching well outside S1, which
  // is a bigger change than the tidiness is worth right now. Kept-with-a-reason
  // is the other disposition AC-S1.11 permits; what it forbids is SILENCE —
  // adding a fifth name beside four dead ones and leaving a later reader unable
  // to tell which is real.
  static const String eventQueueTodoUpdate = 'queue_todo_update';       // DEAD — never emitted
  static const String eventQueueRunningUpdate = 'queue_running_update'; // DEAD — never emitted
  static const String eventQueueDoneUpdate = 'queue_done_update';       // DEAD — never emitted
  static const String eventQueueDeadUpdate = 'queue_dead_update';       // DEAD — never emitted

  /// The LIVE job-status event. Emitted per job by the server at
  /// `pending→queued` (`todo_fifo_queue.py`), `queued→running`
  /// (`queue_consumer.py`) and `running→completed` (`running_fifo_queue.py`);
  /// the completed frame carries the answer in `metadata.response_text`.
  static const String eventJobStateTransition = 'job_state_transition';
  
  // TTS/Audio Events
  static const String eventTtsJobRequest = 'tts_job_request';
  static const String eventAudioStreamingChunk = 'audio_streaming_chunk';
  static const String eventAudioStreamingStatus = 'audio_streaming_status';
  static const String eventAudioStreamingComplete = 'audio_streaming_complete';
  
  // Notification Events
  static const String eventNotificationQueueUpdate = 'notification_queue_update';
  static const String eventNotificationPlaySound = 'notification_play_sound';
  /// Ask LIFECYCLE (AC-S4.3). Both are emitted by
  /// `rest/routers/notifications.py` — `notification_expired` at :1442 with
  /// `{notification_id, default_used, timeout, timestamp}`, and
  /// `notification_responded` at :1636 with
  /// `{notification_id, response_value, …}`. Payload keys sit at the TOP
  /// level of the frame, NOT nested under `notification` the way
  /// `notification_queue_update` nests them.
  ///
  /// Both arrived and were DROPPED before this: neither name appeared
  /// anywhere in `lib/`, so an expired ask stayed "pending" forever and
  /// poisoned `pendingPromptFor`.
  static const String eventNotificationExpired   = 'notification_expired';
  static const String eventNotificationResponded = 'notification_responded';
  
  // Live Console — the Claude Code transcript stream (§3's wire contract).
  //
  // 🔴 THE FOUR NAMES ARE RULED (Q4b) AND THEY CARRY A `cc_` PREFIX FOR A REASON.
  // "transcript" already means speech-to-text on three other surfaces in this system
  // (`/api/v2/transcribe`, `/upload-and-transcribe-{mp3,wav}`, and `transcript` as the
  // name of an STT NDJSON line), so an unprefixed name would be read as audio.
  //
  // ⚠️ AN EVENT NAME MISSING FROM THE SERVER'S INI REGISTRY
  // (`conf/lupin-app.ini:1729` `websocket available events`) VALIDATES AWAY SILENTLY
  // (§3, T3). These are the client's half; the server's half is phase 1's.
  static const String eventTranscriptAppend  = 'cc_transcript_append';
  static const String eventTranscriptState   = 'cc_transcript_state';
  static const String eventTranscriptWatch   = 'cc_transcript_watch';
  static const String eventTranscriptUnwatch = 'cc_transcript_unwatch';

  /// The Live Console's per-seat ring buffer, in BYTES.
  ///
  /// 🔴 PROVISIONAL PENDING OSQ-5, AND A CONSTANT RATHER THAN A LITERAL AT THE USE SITE
  /// (F-Clayton-C9). §5 fixes 256 KB as the provisional default and says in as many words
  /// that it is "read from config, never hard-coded". Open sub-question 5 — what the phone
  /// does when a watched seat's backlog exceeds the buffer — is to be answered together
  /// with §2's Open sub-question 3 on the SERVER's ring size, because the two have to
  /// agree about what "exceeds" means.
  ///
  /// ⚠️ THE UNIT IS BYTES BECAUSE THE SIZE FUNCTION IS SHARED WITH THE SERVER (C8, paired
  /// with A-T7): a block's size is the UTF-8 byte length of its text AFTER server
  /// truncation. A count-of-blocks cap would mean something different on each end.
  static const int transcriptRingBytes = 256 * 1024;

  // System Events
  static const String eventSysTimeUpdate = 'sys_time_update';
  static const String eventSysPing = 'sys_ping';
  static const String eventSysPong = 'sys_pong';
  
  // Authentication Events
  static const String eventAuthRequest = 'auth_request';
  static const String eventAuthSuccess = 'auth_success';
  static const String eventAuthError = 'auth_error';
  static const String eventConnect = 'connect';
  
  // Control Events
  static const String eventUpdateSubscriptions = 'update_subscriptions';
  static const String eventSubscriptionUpdate = 'subscription_update';
  
  // API Endpoints
  static const String apiGetAudio = '/api/get-speech';
  static const String apiGetAudioElevenLabs = '/api/get-speech-elevenlabs';
  static const String apiUploadTranscribe = '/api/upload-and-transcribe-mp3';
  
  // Audio Configuration
  static const int audioSampleRate = 44100;
  static const int audioChunkSize = 8192;
  static const Duration audioTimeout = Duration(seconds: 30);
  
  // Cache Configuration
  static const int maxCacheSize = 104857600; // 100MB
  static const Duration cacheExpiration = Duration(hours: 24);
  
  // UI Configuration
  static const Duration animationDuration = Duration(milliseconds: 300);
  static const Duration splashDuration = Duration(seconds: 2);
  
  // Notification Types
  static const String notificationTypeInfo = 'info';
  static const String notificationTypeWarning = 'warning';
  static const String notificationTypeError = 'error';
  static const String notificationTypeSuccess = 'success';
  static const String notificationTypeAudioResponse = 'audioResponse';
}