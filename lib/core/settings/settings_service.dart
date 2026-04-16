import 'dart:async';
import 'settings_manager.dart';
import '../logging/logger.dart';
import '../error_handling/error_handler.dart';

/// High-level service for settings operations and business logic
class SettingsService {
  static SettingsService? _instance;
  static final Completer<SettingsService> _completer = Completer<SettingsService>();
  
  final SettingsManager _settingsManager;
  final TaggedLogger _logger = Logger.tagged('SettingsService');

  SettingsService._(this._settingsManager);

  /// Get the singleton instance
  static Future<SettingsService> getInstance() async {
    if (_instance == null) {
      final settingsManager = await SettingsManager.getInstance();
      _instance = SettingsService._(settingsManager);
      _completer.complete(_instance);
    }
    return _completer.future;
  }

  // General Settings
  bool get isFirstLaunch => _settingsManager.getSetting<bool>('general.first_launch');
  Future<void> setFirstLaunchCompleted() => _settingsManager.setSetting('general.first_launch', false);

  String get theme => _settingsManager.getSetting<String>('general.theme');
  Future<void> setTheme(String theme) => _settingsManager.setSetting('general.theme', theme);

  String get language => _settingsManager.getSetting<String>('general.language');
  Future<void> setLanguage(String language) => _settingsManager.setSetting('general.language', language);

  // Voice Settings
  bool get isVoiceEnabled => _settingsManager.getSetting<bool>('voice.enabled');
  Future<void> setVoiceEnabled(bool enabled) => _settingsManager.setSetting('voice.enabled', enabled);

  double get voiceSensitivity => _settingsManager.getSetting<double>('voice.sensitivity');
  Future<void> setVoiceSensitivity(double sensitivity) => _settingsManager.setSetting('voice.sensitivity', sensitivity);

  int get maxRecordingDuration => _settingsManager.getSetting<int>('voice.max_recording_duration');
  Future<void> setMaxRecordingDuration(int seconds) => _settingsManager.setSetting('voice.max_recording_duration', seconds);

  String get voiceLanguage => _settingsManager.getSetting<String>('voice.language');
  Future<void> setVoiceLanguage(String language) => _settingsManager.setSetting('voice.language', language);

  // Audio Settings
  bool get isTTSEnabled => _settingsManager.getSetting<bool>('audio.tts_enabled');
  Future<void> setTTSEnabled(bool enabled) => _settingsManager.setSetting('audio.tts_enabled', enabled);

  double get ttsSpeed => _settingsManager.getSetting<double>('audio.tts_speed');
  Future<void> setTTSSpeed(double speed) => _settingsManager.setSetting('audio.tts_speed', speed);

  double get ttsPitch => _settingsManager.getSetting<double>('audio.tts_pitch');
  Future<void> setTTSPitch(double pitch) => _settingsManager.setSetting('audio.tts_pitch', pitch);

  double get audioVolume => _settingsManager.getSetting<double>('audio.volume');
  Future<void> setAudioVolume(double volume) => _settingsManager.setSetting('audio.volume', volume);

  String get ttsVoice => _settingsManager.getSetting<String>('audio.tts_voice');
  Future<void> setTTSVoice(String voice) => _settingsManager.setSetting('audio.tts_voice', voice);

  // Network Settings
  bool get isOfflineMode => _settingsManager.getSetting<bool>('network.offline_mode');
  Future<void> setOfflineMode(bool enabled) => _settingsManager.setSetting('network.offline_mode', enabled);

  int get networkTimeout => _settingsManager.getSetting<int>('network.timeout');
  Future<void> setNetworkTimeout(int seconds) => _settingsManager.setSetting('network.timeout', seconds);

  bool get isWifiOnly => _settingsManager.getSetting<bool>('network.wifi_only');
  Future<void> setWifiOnly(bool enabled) => _settingsManager.setSetting('network.wifi_only', enabled);

  // Privacy Settings
  bool get isAnalyticsEnabled => _settingsManager.getSetting<bool>('privacy.analytics_enabled');
  Future<void> setAnalyticsEnabled(bool enabled) => _settingsManager.setSetting('privacy.analytics_enabled', enabled);

  bool get isCrashReportingEnabled => _settingsManager.getSetting<bool>('privacy.crash_reporting');
  Future<void> setCrashReportingEnabled(bool enabled) => _settingsManager.setSetting('privacy.crash_reporting', enabled);

  int get dataRetentionDays => _settingsManager.getSetting<int>('privacy.data_retention_days');
  Future<void> setDataRetentionDays(int days) => _settingsManager.setSetting('privacy.data_retention_days', days);

  // Accessibility Settings
  bool get isHighContrast => _settingsManager.getSetting<bool>('accessibility.high_contrast');
  Future<void> setHighContrast(bool enabled) => _settingsManager.setSetting('accessibility.high_contrast', enabled);

  double get fontScale => _settingsManager.getSetting<double>('accessibility.font_scale');
  Future<void> setFontScale(double scale) => _settingsManager.setSetting('accessibility.font_scale', scale);

  bool get isVibrationEnabled => _settingsManager.getSetting<bool>('accessibility.vibration_enabled');
  Future<void> setVibrationEnabled(bool enabled) => _settingsManager.setSetting('accessibility.vibration_enabled', enabled);

  // Developer Settings
  bool get isDebugMode => _settingsManager.getSetting<bool>('developer.debug_mode');
  Future<void> setDebugMode(bool enabled) => _settingsManager.setSetting('developer.debug_mode', enabled);

  bool get isVerboseLogging => _settingsManager.getSetting<bool>('developer.verbose_logging');
  Future<void> setVerboseLogging(bool enabled) => _settingsManager.setSetting('developer.verbose_logging', enabled);

  String get apiEndpoint => _settingsManager.getSetting<String>('developer.api_endpoint');
  Future<void> setApiEndpoint(String endpoint) => _settingsManager.setSetting('developer.api_endpoint', endpoint);

  /// Get voice recording configuration
  Map<String, dynamic> getVoiceConfig() {
    return {
      'enabled': isVoiceEnabled,
      'sensitivity': voiceSensitivity,
      'maxDuration': maxRecordingDuration,
      'language': voiceLanguage,
    };
  }

  /// Get TTS configuration
  Map<String, dynamic> getTTSConfig() {
    return {
      'enabled': isTTSEnabled,
      'speed': ttsSpeed,
      'pitch': ttsPitch,
      'volume': audioVolume,
      'voice': ttsVoice,
    };
  }

  /// Get network configuration
  Map<String, dynamic> getNetworkConfig() {
    return {
      'offlineMode': isOfflineMode,
      'timeout': networkTimeout,
      'wifiOnly': isWifiOnly,
      'apiEndpoint': apiEndpoint,
    };
  }

  /// Update voice configuration
  Future<void> updateVoiceConfig({
    bool? enabled,
    double? sensitivity,
    int? maxDuration,
    String? language,
  }) async {
    if (enabled != null) await setVoiceEnabled(enabled);
    if (sensitivity != null) await setVoiceSensitivity(sensitivity);
    if (maxDuration != null) await setMaxRecordingDuration(maxDuration);
    if (language != null) await setVoiceLanguage(language);
  }

  /// Update TTS configuration
  Future<void> updateTTSConfig({
    bool? enabled,
    double? speed,
    double? pitch,
    double? volume,
    String? voice,
  }) async {
    if (enabled != null) await setTTSEnabled(enabled);
    if (speed != null) await setTTSSpeed(speed);
    if (pitch != null) await setTTSPitch(pitch);
    if (volume != null) await setAudioVolume(volume);
    if (voice != null) await setTTSVoice(voice);
  }

  /// Apply quick settings preset
  Future<void> applyQuickPreset(QuickSettingsPreset preset) async {
    _logger.info('Applying quick settings preset: ${preset.name}');
    
    switch (preset) {
      case QuickSettingsPreset.batteryOptimized:
        await updateVoiceConfig(sensitivity: 0.3, maxDuration: 15);
        await updateTTSConfig(enabled: false);
        await setOfflineMode(true);
        break;
        
      case QuickSettingsPreset.highQuality:
        await updateVoiceConfig(sensitivity: 0.7, maxDuration: 60);
        await updateTTSConfig(enabled: true, speed: 1.0, pitch: 1.0);
        await setOfflineMode(false);
        break;
        
      case QuickSettingsPreset.accessibility:
        await setHighContrast(true);
        await setFontScale(1.3);
        await setVibrationEnabled(true);
        await updateTTSConfig(enabled: true, speed: 0.8);
        break;
        
      case QuickSettingsPreset.privacyFocused:
        await setAnalyticsEnabled(false);
        await setCrashReportingEnabled(false);
        await setDataRetentionDays(7);
        await setOfflineMode(true);
        break;
    }
    
    _logger.info('Quick settings preset applied: ${preset.name}');
  }

  /// Validate settings consistency
  Future<List<SettingsValidationIssue>> validateSettings() async {
    final issues = <SettingsValidationIssue>[];
    
    // Voice and TTS consistency
    if (!isVoiceEnabled && isTTSEnabled) {
      issues.add(SettingsValidationIssue(
        type: SettingsValidationIssueType.warning,
        message: 'TTS is enabled but voice input is disabled',
        affectedSettings: ['voice.enabled', 'audio.tts_enabled'],
        suggestion: 'Enable voice input or disable TTS',
      ));
    }
    
    // Network and performance consistency
    if (isWifiOnly && !isOfflineMode) {
      issues.add(SettingsValidationIssue(
        type: SettingsValidationIssueType.info,
        message: 'WiFi-only mode may cause issues without offline mode',
        affectedSettings: ['network.wifi_only', 'network.offline_mode'],
        suggestion: 'Consider enabling offline mode for better reliability',
      ));
    }
    
    // Accessibility and TTS
    if (isHighContrast && fontScale < 1.2) {
      issues.add(SettingsValidationIssue(
        type: SettingsValidationIssueType.suggestion,
        message: 'High contrast is enabled but font scale is small',
        affectedSettings: ['accessibility.high_contrast', 'accessibility.font_scale'],
        suggestion: 'Consider increasing font scale for better readability',
      ));
    }
    
    // Developer settings in production
    if (isDebugMode || isVerboseLogging) {
      issues.add(SettingsValidationIssue(
        type: SettingsValidationIssueType.warning,
        message: 'Developer settings are enabled',
        affectedSettings: ['developer.debug_mode', 'developer.verbose_logging'],
        suggestion: 'Disable developer settings for better performance',
      ));
    }
    
    return issues;
  }

  /// Get settings requiring restart
  List<String> getSettingsRequiringRestart() {
    return _settingsManager.getSettingsRequiringRestart();
  }

  /// Export settings
  Map<String, dynamic> exportSettings() {
    return _settingsManager.exportSettings();
  }

  /// Import settings
  Future<void> importSettings(Map<String, dynamic> data) async {
    await _settingsManager.importSettings(data);
  }

  /// Reset settings category
  Future<void> resetCategory(SettingsCategory category) async {
    await _settingsManager.resetCategory(category);
  }

  /// Reset all settings
  Future<void> resetAllSettings() async {
    await _settingsManager.resetAllSettings();
  }

  /// Listen to settings changes
  Stream<SettingsChangedEvent> get onSettingsChanged => _settingsManager.onSettingsChanged;

  /// Get settings manager for advanced operations
  SettingsManager get manager => _settingsManager;
}

/// Quick settings presets
enum QuickSettingsPreset {
  batteryOptimized,
  highQuality,
  accessibility,
  privacyFocused,
}

extension QuickSettingsPresetExtension on QuickSettingsPreset {
  String get name {
    switch (this) {
      case QuickSettingsPreset.batteryOptimized:
        return 'Battery Optimized';
      case QuickSettingsPreset.highQuality:
        return 'High Quality';
      case QuickSettingsPreset.accessibility:
        return 'Accessibility';
      case QuickSettingsPreset.privacyFocused:
        return 'Privacy Focused';
    }
  }

  String get description {
    switch (this) {
      case QuickSettingsPreset.batteryOptimized:
        return 'Optimized for battery life and performance';
      case QuickSettingsPreset.highQuality:
        return 'Best quality voice and audio experience';
      case QuickSettingsPreset.accessibility:
        return 'Enhanced accessibility features';
      case QuickSettingsPreset.privacyFocused:
        return 'Maximum privacy and data protection';
    }
  }
}

/// Settings validation issue
class SettingsValidationIssue {
  final SettingsValidationIssueType type;
  final String message;
  final List<String> affectedSettings;
  final String? suggestion;

  const SettingsValidationIssue({
    required this.type,
    required this.message,
    required this.affectedSettings,
    this.suggestion,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'message': message,
      'affectedSettings': affectedSettings,
      'suggestion': suggestion,
    };
  }
}

/// Settings validation issue types
enum SettingsValidationIssueType {
  error,
  warning,
  info,
  suggestion,
}