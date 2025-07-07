class AppConstants {
  AppConstants._();
  
  // App Information
  static const String appName = 'Lupin Mobile';
  static const String appVersion = '1.0.0';
  
  // API Configuration
  static const String apiBaseUrl = 'http://localhost:7999';
  static const String wsBaseUrl = 'ws://localhost:7999';
  
  // WebSocket Endpoints
  static const String wsEndpoint = '/ws';
  static const String wsQueueEndpoint = '/ws/queue';
  
  // API Endpoints
  static const String apiGetAudio = '/api/get-audio';
  static const String apiGetAudioElevenLabs = '/api/get-audio-elevenlabs';
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