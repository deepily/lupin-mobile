class AppConstants {
  AppConstants._();
  
  // App Information
  static const String appName = 'Lupin Mobile';
  static const String appVersion = '1.0.0';
  
  // API Configuration
  // NOTE: These are runtime-mutable. ServerContextService rewrites them
  // when the user toggles Dev ↔ Test in settings. Defaults match Dev.
  static String apiBaseUrl = 'http://localhost:7999';
  static String wsBaseUrl  = 'ws://localhost:7999';
  
  // WebSocket Endpoints
  static const String wsQueueEndpoint = '/ws/queue';
  static const String wsAudioEndpoint = '/ws/audio';
  
  // WebSocket Event Types
  // Queue Events
  static const String eventQueueTodoUpdate = 'queue_todo_update';
  static const String eventQueueRunningUpdate = 'queue_running_update';
  static const String eventQueueDoneUpdate = 'queue_done_update';
  static const String eventQueueDeadUpdate = 'queue_dead_update';
  
  // TTS/Audio Events
  static const String eventTtsJobRequest = 'tts_job_request';
  static const String eventAudioStreamingChunk = 'audio_streaming_chunk';
  static const String eventAudioStreamingStatus = 'audio_streaming_status';
  static const String eventAudioStreamingComplete = 'audio_streaming_complete';
  
  // Notification Events
  static const String eventNotificationQueueUpdate = 'notification_queue_update';
  static const String eventNotificationPlaySound = 'notification_play_sound';
  
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