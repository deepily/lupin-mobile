/// App-wide constants: server paths, WebSocket event names and tuning values.
///
/// The API base URLs are mutable at runtime, and the rest are compile-time constants.
class AppConstants {
  AppConstants._();
  
  // App Information
  /// Display name of the app.
  static const String appName = 'Lupin Mobile';

  /// App version string.
  static const String appVersion = '1.0.0';
  
  // API Configuration
  // These are runtime-mutable. ServerContextService rewrites them when the user toggles
  // Dev and Test in settings. The defaults match Dev.
  // 10.0.2.2 is the Android emulator's host-loopback alias, which maps to the host's 127.0.0.1.
  // Desktop and iOS would need localhost, so revisit this if those targets are added.
  /// Base URL of the HTTP API; ServerContextService rewrites it on a context change.
  static String apiBaseUrl = 'http://10.0.2.2:7999';

  /// Base URL of the WebSocket endpoint; ServerContextService rewrites it on a context change.
  static String wsBaseUrl  = 'ws://10.0.2.2:7999';
  
  // WebSocket Endpoints
  /// Path of the queue WebSocket.
  static const String wsQueueEndpoint = '/ws/queue';

  /// Path of the audio WebSocket.
  static const String wsAudioEndpoint = '/ws/audio';
  
  // WebSocket Event Types
  // Queue Events
  //
  // The four queue update events below are never emitted by the server.
  // They have no emit sites in the Lupin backend and are absent from the INI's `websocket available events`;
  // the parent repo measured this (`src/tests/lupin_smoke/test_queue_workflow.py`).
  // The live event that carries job status is `eventJobStateTransition`.
  //
  // They are kept rather than deleted, with this reason: four WebSocket services that no section of the
  // Quick Ask plan owns reference them (`websocket_message_router.dart`, `websocket_subscription_manager.dart`,
  // `websocket_dynamic_subscription_controller.dart`), as do several test helpers.
  // Removing them is a roughly 40-site edit well outside the Quick Ask work, which is a bigger change than the tidiness is worth.
  // Kept with a reason is acceptable; adding a fifth name beside four dead ones and leaving a later reader
  // unable to tell which is real is not.
  // Design: src/docs/decisions/README.md (R-CORE-dead-queue-events)
  /// Dead: the server never emits it; see the comment above.
  static const String eventQueueTodoUpdate = 'queue_todo_update';

  /// Dead: the server never emits it; see the comment above.
  static const String eventQueueRunningUpdate = 'queue_running_update';

  /// Dead: the server never emits it; see the comment above.
  static const String eventQueueDoneUpdate = 'queue_done_update';

  /// Dead: the server never emits it; see the comment above.
  static const String eventQueueDeadUpdate = 'queue_dead_update';

  /// The live job-status event, emitted per job at each transition.
  ///
  /// The server emits it at pending to queued (`todo_fifo_queue.py`), queued to running (`queue_consumer.py`)
  /// and running to completed (`running_fifo_queue.py`). The completed frame carries the answer in `metadata.response_text`.
  static const String eventJobStateTransition = 'job_state_transition';
  
  // TTS/Audio Events
  /// Event name for a TTS job request.
  static const String eventTtsJobRequest = 'tts_job_request';

  /// Event carrying one chunk of streamed TTS audio.
  static const String eventAudioStreamingChunk = 'audio_streaming_chunk';

  /// Event name for a TTS streaming status update.
  static const String eventAudioStreamingStatus = 'audio_streaming_status';

  /// Event that ends a TTS audio stream.
  static const String eventAudioStreamingComplete = 'audio_streaming_complete';
  
  // Notification Events
  /// Event carrying a new or changed notification item.
  static const String eventNotificationQueueUpdate = 'notification_queue_update';

  /// Event asking the client to play a notification sound.
  static const String eventNotificationPlaySound = 'notification_play_sound';

  /// Ask lifecycle event: a notification that asked a question expired.
  ///
  /// `rest/routers/notifications.py` emits it with `{notification_id, default_used, timeout, timestamp}`.
  /// Payload keys sit at the top level of the frame, not nested under `notification` as in `notification_queue_update`.
  /// Before the client handled it, an expired ask stayed pending forever and poisoned `pendingPromptFor`.
  static const String eventNotificationExpired   = 'notification_expired';

  /// Ask lifecycle event: a notification that asked a question was answered.
  ///
  /// `rest/routers/notifications.py` emits it with `{notification_id, response_value, ...}`.
  /// Payload keys sit at the top level of the frame, not nested under `notification`.
  static const String eventNotificationResponded = 'notification_responded';
  
  // Live Console — the Claude Code transcript stream.
  //
  // The four names carry a `cc_` prefix for a reason. "Transcript" already means speech-to-text on three other
  // surfaces in this system (`/api/v2/transcribe`, `/upload-and-transcribe-{mp3,wav}`, and `transcript` as the
  // name of an STT NDJSON line), so an unprefixed name would be read as audio.
  // Design: src/docs/decisions/README.md (R-CORE-cc-prefix)
  //
  // An event name missing from the server's INI registry (`conf/lupin-app.ini`, `websocket available events`)
  // validates away silently. These are the client's half; the server's half is separate.
  /// Event appending blocks to a watched seat's transcript.
  static const String eventTranscriptAppend  = 'cc_transcript_append';

  /// Event reporting a watched seat's transcript state.
  static const String eventTranscriptState   = 'cc_transcript_state';

  /// Event asking the server to start streaming a seat's transcript.
  static const String eventTranscriptWatch   = 'cc_transcript_watch';

  /// Event asking the server to stop streaming a seat's transcript.
  static const String eventTranscriptUnwatch = 'cc_transcript_unwatch';

  /// The Live Console's per-seat ring buffer size, in bytes.
  ///
  /// The 256 KB default is provisional. It is a constant, not a literal at the use site, because it is meant to be read from config.
  /// What the phone does when a watched seat's backlog exceeds the buffer is still open.
  /// It is to be settled together with the server's ring size, because the two must agree on what "exceeds" means.
  /// The unit is bytes because the size function is shared with the server.
  /// A block's size is the UTF-8 byte length of its text after server truncation.
  /// A count-of-blocks cap would mean something different on each end.
  static const int transcriptRingBytes = 256 * 1024;

  // System Events
  /// Server time update event.
  static const String eventSysTimeUpdate = 'sys_time_update';

  /// Keepalive ping.
  static const String eventSysPing = 'sys_ping';

  /// Keepalive pong.
  static const String eventSysPong = 'sys_pong';
  
  // Authentication Events
  /// Client request to authenticate the socket.
  static const String eventAuthRequest = 'auth_request';

  /// Server reply that authentication succeeded.
  static const String eventAuthSuccess = 'auth_success';

  /// Server frame that ends a resume replay.
  static const String eventResumeComplete = 'resume_complete';

  /// Server reply that authentication failed.
  static const String eventAuthError = 'auth_error';

  /// Connection event name.
  static const String eventConnect = 'connect';
  
  // Control Events
  /// Client request to change its event subscriptions.
  static const String eventUpdateSubscriptions = 'update_subscriptions';

  /// Server confirmation of a subscription change.
  static const String eventSubscriptionUpdate = 'subscription_update';
  
  // API Endpoints
  /// Path of the default text-to-speech endpoint.
  static const String apiGetAudio = '/api/get-speech';

  /// Path of the ElevenLabs text-to-speech endpoint.
  static const String apiGetAudioElevenLabs = '/api/get-speech-elevenlabs';

  /// Path of the MP3 upload-and-transcribe endpoint.
  static const String apiUploadTranscribe = '/api/upload-and-transcribe-mp3';
  
  // Audio Configuration
  /// Audio sample rate, in hertz.
  static const int audioSampleRate = 44100;

  /// Audio chunk size, in bytes.
  static const int audioChunkSize = 8192;

  /// Timeout for audio operations.
  static const Duration audioTimeout = Duration(seconds: 30);
  
  // Cache Configuration
  /// Maximum cache size in bytes: 100 MB.
  static const int maxCacheSize = 104857600;

  /// How long a cache entry stays valid.
  static const Duration cacheExpiration = Duration(hours: 24);
  
  // UI Configuration
  /// Standard UI animation duration.
  static const Duration animationDuration = Duration(milliseconds: 300);

  /// How long the splash screen shows.
  static const Duration splashDuration = Duration(seconds: 2);
  
  // Notification Types
  /// Notification type: informational.
  static const String notificationTypeInfo = 'info';

  /// Notification type: warning.
  static const String notificationTypeWarning = 'warning';

  /// Notification type: error.
  static const String notificationTypeError = 'error';

  /// Notification type: success.
  static const String notificationTypeSuccess = 'success';

  /// Notification type: audio response.
  static const String notificationTypeAudioResponse = 'audioResponse';
}
