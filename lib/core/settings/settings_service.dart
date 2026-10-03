import 'dart:async';
import 'settings_manager.dart';
import '../logging/logger.dart';

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
  /// True until [setFirstLaunchCompleted] has run.
  bool get isFirstLaunch => _settingsManager.getSetting<bool>('general.first_launch');
  /// Marks the first launch as done.
  Future<void> setFirstLaunchCompleted() => _settingsManager.setSetting('general.first_launch', false);

  /// Theme preference.
  String get theme => _settingsManager.getSetting<String>('general.theme');
  /// Stores the theme preference.
  Future<void> setTheme(String theme) => _settingsManager.setSetting('general.theme', theme);

  /// App language.
  String get language => _settingsManager.getSetting<String>('general.language');
  /// Stores the app language.
  Future<void> setLanguage(String language) => _settingsManager.setSetting('general.language', language);

  // Voice Settings
  /// Whether voice input is on.
  bool get isVoiceEnabled => _settingsManager.getSetting<bool>('voice.enabled');
  /// Turns voice input on or off.
  Future<void> setVoiceEnabled(bool enabled) => _settingsManager.setSetting('voice.enabled', enabled);

  /// Microphone sensitivity level.
  double get voiceSensitivity => _settingsManager.getSetting<double>('voice.sensitivity');
  /// Stores the microphone sensitivity level.
  Future<void> setVoiceSensitivity(double sensitivity) => _settingsManager.setSetting('voice.sensitivity', sensitivity);

  /// Longest recording allowed, in seconds.
  int get maxRecordingDuration => _settingsManager.getSetting<int>('voice.max_recording_duration');
  /// Stores the longest recording allowed, in seconds.
  Future<void> setMaxRecordingDuration(int seconds) => _settingsManager.setSetting('voice.max_recording_duration', seconds);

  /// Language used for voice recognition.
  String get voiceLanguage => _settingsManager.getSetting<String>('voice.language');
  /// Stores the voice-recognition language.
  Future<void> setVoiceLanguage(String language) => _settingsManager.setSetting('voice.language', language);

  // Audio Settings
  /// Whether audio responses are on.
  bool get isTTSEnabled => _settingsManager.getSetting<bool>('audio.tts_enabled');
  /// Turns audio responses on or off.
  Future<void> setTTSEnabled(bool enabled) => _settingsManager.setSetting('audio.tts_enabled', enabled);

  /// Text-to-speech playback speed.
  double get ttsSpeed => _settingsManager.getSetting<double>('audio.tts_speed');
  /// Stores the text-to-speech playback speed.
  Future<void> setTTSSpeed(double speed) => _settingsManager.setSetting('audio.tts_speed', speed);

  /// Text-to-speech pitch.
  double get ttsPitch => _settingsManager.getSetting<double>('audio.tts_pitch');
  /// Stores the text-to-speech pitch.
  Future<void> setTTSPitch(double pitch) => _settingsManager.setSetting('audio.tts_pitch', pitch);

  /// Default audio volume.
  double get audioVolume => _settingsManager.getSetting<double>('audio.volume');
  /// Stores the default audio volume.
  Future<void> setAudioVolume(double volume) => _settingsManager.setSetting('audio.volume', volume);

  /// Selected text-to-speech voice.
  String get ttsVoice => _settingsManager.getSetting<String>('audio.tts_voice');
  /// Stores the selected text-to-speech voice.
  Future<void> setTTSVoice(String voice) => _settingsManager.setSetting('audio.tts_voice', voice);

  // Network Settings
  /// Whether cached data is used where possible.
  bool get isOfflineMode => _settingsManager.getSetting<bool>('network.offline_mode');
  /// Turns offline mode on or off.
  Future<void> setOfflineMode(bool enabled) => _settingsManager.setSetting('network.offline_mode', enabled);

  /// Network request timeout, in seconds.
  int get networkTimeout => _settingsManager.getSetting<int>('network.timeout');
  /// Stores the network request timeout, in seconds.
  Future<void> setNetworkTimeout(int seconds) => _settingsManager.setSetting('network.timeout', seconds);

  /// Whether network requests use Wi-Fi only.
  bool get isWifiOnly => _settingsManager.getSetting<bool>('network.wifi_only');
  /// Turns the Wi-Fi-only restriction on or off.
  Future<void> setWifiOnly(bool enabled) => _settingsManager.setSetting('network.wifi_only', enabled);

  // Privacy Settings
  /// Whether anonymous usage analytics are allowed.
  bool get isAnalyticsEnabled => _settingsManager.getSetting<bool>('privacy.analytics_enabled');
  /// Allows or blocks anonymous usage analytics.
  Future<void> setAnalyticsEnabled(bool enabled) => _settingsManager.setSetting('privacy.analytics_enabled', enabled);

  /// Whether crash reports are sent.
  bool get isCrashReportingEnabled => _settingsManager.getSetting<bool>('privacy.crash_reporting');
  /// Turns crash reporting on or off.
  Future<void> setCrashReportingEnabled(bool enabled) => _settingsManager.setSetting('privacy.crash_reporting', enabled);

  /// Days local voice data is kept.
  int get dataRetentionDays => _settingsManager.getSetting<int>('privacy.data_retention_days');
  /// Stores how many days local voice data is kept.
  Future<void> setDataRetentionDays(int days) => _settingsManager.setSetting('privacy.data_retention_days', days);

  // Accessibility Settings
  /// Whether high-contrast colors are used.
  bool get isHighContrast => _settingsManager.getSetting<bool>('accessibility.high_contrast');
  /// Turns high-contrast colors on or off.
  Future<void> setHighContrast(bool enabled) => _settingsManager.setSetting('accessibility.high_contrast', enabled);

  /// Text size multiplier.
  double get fontScale => _settingsManager.getSetting<double>('accessibility.font_scale');
  /// Stores the text size multiplier.
  Future<void> setFontScale(double scale) => _settingsManager.setSetting('accessibility.font_scale', scale);

  /// Whether haptic feedback is on.
  bool get isVibrationEnabled => _settingsManager.getSetting<bool>('accessibility.vibration_enabled');
  /// Turns haptic feedback on or off.
  Future<void> setVibrationEnabled(bool enabled) => _settingsManager.setSetting('accessibility.vibration_enabled', enabled);

  // Developer Settings
  /// Whether debug features are on.
  bool get isDebugMode => _settingsManager.getSetting<bool>('developer.debug_mode');
  /// Turns debug features on or off.
  Future<void> setDebugMode(bool enabled) => _settingsManager.setSetting('developer.debug_mode', enabled);

  /// Whether detailed logging is on.
  bool get isVerboseLogging => _settingsManager.getSetting<bool>('developer.verbose_logging');
  /// Turns detailed logging on or off.
  Future<void> setVerboseLogging(bool enabled) => _settingsManager.setSetting('developer.verbose_logging', enabled);

  /// Custom API endpoint URL.
  String get apiEndpoint => _settingsManager.getSetting<String>('developer.api_endpoint');
  /// Stores the custom API endpoint URL.
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

  /// Applies the given voice settings and leaves the rest unchanged
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

  /// Applies the given text-to-speech settings and leaves the rest unchanged
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
  /// Favors battery life and performance.
  batteryOptimized,
  /// Best voice and audio quality.
  highQuality,
  /// Enhanced accessibility features.
  accessibility,
  /// Maximum privacy and data protection.
  privacyFocused,
}

/// Display name and description of a [QuickSettingsPreset].
extension QuickSettingsPresetExtension on QuickSettingsPreset {
  /// Name shown to the user.
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

  /// One-line description shown to the user.
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
  /// Severity of the issue.
  final SettingsValidationIssueType type;
  /// What is wrong.
  final String message;
  /// Keys of the settings involved.
  final List<String> affectedSettings;
  /// Suggested fix, or null.
  final String? suggestion;

  /// Creates an issue; [suggestion] is optional.
  const SettingsValidationIssue({
    required this.type,
    required this.message,
    required this.affectedSettings,
    this.suggestion,
  });

  /// Serializes the issue.
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
  /// A setting combination that is wrong.
  error,
  /// A setting combination that may cause trouble.
  warning,
  /// Information about the settings.
  info,
  /// A suggested improvement.
  suggestion,
}