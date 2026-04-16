import 'package:get_it/get_it.dart';
import '../logging/logger.dart';

// Voice use cases
import '../../features/voice/use_cases/start_voice_recording_use_case.dart';
import '../../features/voice/use_cases/stop_voice_recording_use_case.dart';
import '../../features/voice/use_cases/process_voice_input_use_case.dart';
import '../../features/voice/use_cases/voice_interaction_orchestrator.dart';

// Session use cases
import '../../features/session/use_cases/create_session_use_case.dart';

// Audio use cases
import '../../features/audio/use_cases/generate_tts_audio_use_case.dart';

// Settings use cases
import '../../features/settings/use_cases/settings_use_cases.dart';

// Repository interfaces
import '../repositories/interfaces/voice_repository.dart';
import '../repositories/interfaces/session_repository.dart';
import '../repositories/interfaces/user_repository.dart';
import '../repositories/interfaces/job_repository.dart';
import '../repositories/interfaces/audio_repository.dart';

// Settings services
import '../settings/settings_service.dart';

/// Registry for all use cases in the application
class UseCaseRegistry {
  static final TaggedLogger _logger = Logger.tagged('UseCaseRegistry');
  static bool _initialized = false;

  /// Initialize and register all use cases
  static Future<void> initialize() async {
    if (_initialized) {
      _logger.warning('Use case registry already initialized');
      return;
    }

    _logger.info('Initializing use case registry...');

    try {
      // Register voice use cases
      _registerVoiceUseCases();
      
      // Register session use cases
      _registerSessionUseCases();
      
      // Register audio use cases
      _registerAudioUseCases();
      
      // Register composite use cases
      _registerCompositeUseCases();
      
      // Register settings use cases
      _registerSettingsUseCases();

      _initialized = true;
      _logger.info('Use case registry initialized successfully');

    } catch (error, stackTrace) {
      _logger.error(
        'Failed to initialize use case registry',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Register voice-related use cases
  static void _registerVoiceUseCases() {
    final getIt = GetIt.instance;

    // Start voice recording
    getIt.registerFactory<StartVoiceRecordingUseCase>(
      () => StartVoiceRecordingUseCase(
        getIt<VoiceRepository>(),
        getIt<SessionRepository>(),
      ),
    );

    // Stop voice recording
    getIt.registerFactory<StopVoiceRecordingUseCase>(
      () => StopVoiceRecordingUseCase(
        getIt<VoiceRepository>(),
      ),
    );

    // Process voice input
    getIt.registerFactory<ProcessVoiceInputUseCase>(
      () => ProcessVoiceInputUseCase(
        getIt<VoiceRepository>(),
        getIt<JobRepository>(),
      ),
    );

    // Watch voice processing progress
    getIt.registerFactory<WatchVoiceProcessingProgressUseCase>(
      () => WatchVoiceProcessingProgressUseCase(
        getIt<VoiceRepository>(),
      ),
    );

    _logger.debug('Voice use cases registered');
  }

  /// Register session-related use cases
  static void _registerSessionUseCases() {
    final getIt = GetIt.instance;

    // Create session
    getIt.registerFactory<CreateSessionUseCase>(
      () => CreateSessionUseCase(
        getIt<SessionRepository>(),
        getIt<UserRepository>(),
      ),
    );

    // Validate session
    getIt.registerFactory<ValidateSessionUseCase>(
      () => ValidateSessionUseCase(
        getIt<SessionRepository>(),
      ),
    );

    // Terminate session
    getIt.registerFactory<TerminateSessionUseCase>(
      () => TerminateSessionUseCase(
        getIt<SessionRepository>(),
      ),
    );

    _logger.debug('Session use cases registered');
  }

  /// Register audio-related use cases
  static void _registerAudioUseCases() {
    final getIt = GetIt.instance;

    // Generate TTS audio
    getIt.registerFactory<GenerateTTSAudioUseCase>(
      () => GenerateTTSAudioUseCase(
        getIt<VoiceRepository>(),
        getIt<JobRepository>(),
        getIt<AudioRepository>(),
      ),
    );

    // Play audio
    getIt.registerFactory<PlayAudioUseCase>(
      () => PlayAudioUseCase(
        getIt<AudioRepository>(),
      ),
    );

    // Stop audio
    getIt.registerFactory<StopAudioUseCase>(
      () => StopAudioUseCase(
        getIt<AudioRepository>(),
      ),
    );

    // Watch audio generation progress
    getIt.registerFactory<WatchAudioGenerationProgressUseCase>(
      () => WatchAudioGenerationProgressUseCase(
        getIt<AudioRepository>(),
      ),
    );

    _logger.debug('Audio use cases registered');
  }

  /// Register composite/orchestrator use cases
  static void _registerCompositeUseCases() {
    final getIt = GetIt.instance;

    // Voice interaction orchestrator
    getIt.registerFactory<VoiceInteractionOrchestrator>(
      () => VoiceInteractionOrchestrator(
        getIt<StartVoiceRecordingUseCase>(),
        getIt<StopVoiceRecordingUseCase>(),
        getIt<ProcessVoiceInputUseCase>(),
        getIt<GenerateTTSAudioUseCase>(),
        getIt<WatchVoiceProcessingProgressUseCase>(),
      ),
    );

    // Quick voice interaction
    getIt.registerFactory<QuickVoiceInteractionUseCase>(
      () => QuickVoiceInteractionUseCase(
        getIt<VoiceInteractionOrchestrator>(),
      ),
    );

    _logger.debug('Composite use cases registered');
  }

  /// Register settings-related use cases
  static void _registerSettingsUseCases() {
    final getIt = GetIt.instance;

    // Update settings
    getIt.registerFactory<UpdateSettingsUseCase>(
      () => UpdateSettingsUseCase(
        getIt<SettingsService>(),
      ),
    );

    // Apply settings preset
    getIt.registerFactory<ApplySettingsPresetUseCase>(
      () => ApplySettingsPresetUseCase(
        getIt<SettingsService>(),
      ),
    );

    // Get settings by category
    getIt.registerFactory<GetSettingsByCategoryUseCase>(
      () => GetSettingsByCategoryUseCase(
        getIt<SettingsService>(),
      ),
    );

    // Validate settings
    getIt.registerFactory<ValidateSettingsUseCase>(
      () => ValidateSettingsUseCase(
        getIt<SettingsService>(),
      ),
    );

    // Import settings
    getIt.registerFactory<ImportSettingsUseCase>(
      () => ImportSettingsUseCase(
        getIt<SettingsService>(),
      ),
    );

    // Export settings
    getIt.registerFactory<ExportSettingsUseCase>(
      () => ExportSettingsUseCase(
        getIt<SettingsService>(),
      ),
    );

    // Reset settings
    getIt.registerFactory<ResetSettingsUseCase>(
      () => ResetSettingsUseCase(
        getIt<SettingsService>(),
      ),
    );

    // Watch settings changes
    getIt.registerFactory<WatchSettingsChangesUseCase>(
      () => WatchSettingsChangesUseCase(
        getIt<SettingsService>(),
      ),
    );

    _logger.debug('Settings use cases registered');
  }

  /// Get a use case instance
  static T getUseCase<T extends Object>() {
    if (!_initialized) {
      throw StateError('Use case registry not initialized');
    }
    
    try {
      return GetIt.instance.get<T>();
    } catch (error) {
      _logger.error('Failed to get use case: $T', error: error);
      rethrow;
    }
  }

  /// Check if use case registry is initialized
  static bool get isInitialized => _initialized;

  /// Dispose all use cases
  static void dispose() {
    if (!_initialized) return;

    _logger.info('Disposing use case registry...');
    
    // GetIt will handle disposal of registered instances
    // Individual use cases don't need special disposal
    
    _initialized = false;
    _logger.info('Use case registry disposed');
  }
}

/// Extension methods for easier use case access
extension UseCaseAccess on GetIt {
  // Voice use cases
  StartVoiceRecordingUseCase get startVoiceRecording => 
      UseCaseRegistry.getUseCase<StartVoiceRecordingUseCase>();
  
  StopVoiceRecordingUseCase get stopVoiceRecording => 
      UseCaseRegistry.getUseCase<StopVoiceRecordingUseCase>();
  
  ProcessVoiceInputUseCase get processVoiceInput => 
      UseCaseRegistry.getUseCase<ProcessVoiceInputUseCase>();
  
  WatchVoiceProcessingProgressUseCase get watchVoiceProgress => 
      UseCaseRegistry.getUseCase<WatchVoiceProcessingProgressUseCase>();

  // Session use cases
  CreateSessionUseCase get createSession => 
      UseCaseRegistry.getUseCase<CreateSessionUseCase>();
  
  ValidateSessionUseCase get validateSession => 
      UseCaseRegistry.getUseCase<ValidateSessionUseCase>();
  
  TerminateSessionUseCase get terminateSession => 
      UseCaseRegistry.getUseCase<TerminateSessionUseCase>();

  // Audio use cases
  GenerateTTSAudioUseCase get generateTTSAudio => 
      UseCaseRegistry.getUseCase<GenerateTTSAudioUseCase>();
  
  PlayAudioUseCase get playAudio => 
      UseCaseRegistry.getUseCase<PlayAudioUseCase>();
  
  StopAudioUseCase get stopAudio => 
      UseCaseRegistry.getUseCase<StopAudioUseCase>();
  
  WatchAudioGenerationProgressUseCase get watchAudioProgress => 
      UseCaseRegistry.getUseCase<WatchAudioGenerationProgressUseCase>();

  // Composite use cases
  VoiceInteractionOrchestrator get voiceInteractionOrchestrator => 
      UseCaseRegistry.getUseCase<VoiceInteractionOrchestrator>();
  
  QuickVoiceInteractionUseCase get quickVoiceInteraction => 
      UseCaseRegistry.getUseCase<QuickVoiceInteractionUseCase>();

  // Settings use cases
  UpdateSettingsUseCase get updateSettings => 
      UseCaseRegistry.getUseCase<UpdateSettingsUseCase>();
  
  ApplySettingsPresetUseCase get applySettingsPreset => 
      UseCaseRegistry.getUseCase<ApplySettingsPresetUseCase>();
  
  GetSettingsByCategoryUseCase get getSettingsByCategory => 
      UseCaseRegistry.getUseCase<GetSettingsByCategoryUseCase>();
  
  ValidateSettingsUseCase get validateSettings => 
      UseCaseRegistry.getUseCase<ValidateSettingsUseCase>();
  
  ImportSettingsUseCase get importSettings => 
      UseCaseRegistry.getUseCase<ImportSettingsUseCase>();
  
  ExportSettingsUseCase get exportSettings => 
      UseCaseRegistry.getUseCase<ExportSettingsUseCase>();
  
  ResetSettingsUseCase get resetSettings => 
      UseCaseRegistry.getUseCase<ResetSettingsUseCase>();
  
  WatchSettingsChangesUseCase get watchSettingsChanges => 
      UseCaseRegistry.getUseCase<WatchSettingsChangesUseCase>();
}

/// Use case metrics and monitoring
class UseCaseMetrics {
  static final Map<String, List<Duration>> _executionTimes = {};
  static final Map<String, int> _successCounts = {};
  static final Map<String, int> _failureCounts = {};

  /// Record use case execution
  static void recordExecution(
    String useCaseName,
    Duration executionTime,
    bool success,
  ) {
    _executionTimes.putIfAbsent(useCaseName, () => []).add(executionTime);
    
    if (success) {
      _successCounts[useCaseName] = (_successCounts[useCaseName] ?? 0) + 1;
    } else {
      _failureCounts[useCaseName] = (_failureCounts[useCaseName] ?? 0) + 1;
    }
  }

  /// Get metrics for a use case
  static Map<String, dynamic> getMetrics(String useCaseName) {
    final executionTimes = _executionTimes[useCaseName] ?? [];
    final successCount = _successCounts[useCaseName] ?? 0;
    final failureCount = _failureCounts[useCaseName] ?? 0;
    final totalCount = successCount + failureCount;

    if (executionTimes.isEmpty) {
      return {
        'use_case': useCaseName,
        'total_executions': 0,
        'success_rate': 0.0,
      };
    }

    final avgTime = executionTimes.fold<int>(
      0,
      (sum, duration) => sum + duration.inMilliseconds,
    ) / executionTimes.length;

    return {
      'use_case': useCaseName,
      'total_executions': totalCount,
      'success_count': successCount,
      'failure_count': failureCount,
      'success_rate': totalCount > 0 ? successCount / totalCount : 0.0,
      'average_execution_time_ms': avgTime.round(),
      'min_execution_time_ms': executionTimes.map((d) => d.inMilliseconds).reduce((a, b) => a < b ? a : b),
      'max_execution_time_ms': executionTimes.map((d) => d.inMilliseconds).reduce((a, b) => a > b ? a : b),
    };
  }

  /// Get all metrics
  static Map<String, dynamic> getAllMetrics() {
    final allUseCases = {
      ..._executionTimes.keys,
      ..._successCounts.keys,
      ..._failureCounts.keys,
    };

    return {
      'summary': {
        'total_use_cases': allUseCases.length,
        'timestamp': DateTime.now().toIso8601String(),
      },
      'use_cases': allUseCases.map((name) => getMetrics(name)).toList(),
    };
  }

  /// Clear all metrics
  static void clear() {
    _executionTimes.clear();
    _successCounts.clear();
    _failureCounts.clear();
  }
}