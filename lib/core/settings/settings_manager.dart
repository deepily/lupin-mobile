import 'dart:async';
import 'dart:convert';
import '../storage/storage_manager.dart';
import '../logging/logger.dart';
import '../error_handling/error_handler.dart';

/// Settings categories for organization
enum SettingsCategory {
  general,
  voice,
  audio,
  network,
  privacy,
  accessibility,
  developer,
}

/// Setting types for validation and UI generation
enum SettingType {
  boolean,
  integer,
  double,
  string,
  list,
  map,
  enum_,
}

/// Individual setting definition
class SettingDefinition<T> {
  final String key;
  final SettingsCategory category;
  final SettingType type;
  final T defaultValue;
  final String title;
  final String? description;
  final T? minValue;
  final T? maxValue;
  final List<T>? allowedValues;
  final bool requiresRestart;
  final bool isAdvanced;
  final bool Function(T value)? validator;

  const SettingDefinition({
    required this.key,
    required this.category,
    required this.type,
    required this.defaultValue,
    required this.title,
    this.description,
    this.minValue,
    this.maxValue,
    this.allowedValues,
    this.requiresRestart = false,
    this.isAdvanced = false,
    this.validator,
  });

  /// Validate a value against this setting definition
  bool isValid(T value) {
    // Type validation is handled by Dart's type system
    
    // Range validation
    if (minValue != null && value is Comparable && (value as Comparable).compareTo(minValue!) < 0) {
      return false;
    }
    if (maxValue != null && value is Comparable && (value as Comparable).compareTo(maxValue!) > 0) {
      return false;
    }
    
    // Allowed values validation
    if (allowedValues != null && !allowedValues!.contains(value)) {
      return false;
    }
    
    // Custom validation
    if (validator != null && !validator!(value)) {
      return false;
    }
    
    return true;
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'category': category.name,
      'type': type.name,
      'defaultValue': defaultValue,
      'title': title,
      'description': description,
      'minValue': minValue,
      'maxValue': maxValue,
      'allowedValues': allowedValues,
      'requiresRestart': requiresRestart,
      'isAdvanced': isAdvanced,
    };
  }
}

/// Settings manager for handling user preferences and app configuration
class SettingsManager {
  static SettingsManager? _instance;
  static final Completer<SettingsManager> _completer = Completer<SettingsManager>();
  
  final StorageManager _storage;
  final TaggedLogger _logger = Logger.tagged('SettingsManager');
  final Map<String, SettingDefinition> _definitions = {};
  final Map<String, dynamic> _cache = {};
  final StreamController<SettingsChangedEvent> _changesController = StreamController.broadcast();

  SettingsManager._(this._storage) {
    _registerDefaultSettings();
  }

  /// Get the singleton instance
  static Future<SettingsManager> getInstance() async {
    if (_instance == null) {
      final storage = await StorageManager.getInstance();
      _instance = SettingsManager._(storage);
      await _instance!._initialize();
      _completer.complete(_instance);
    }
    return _completer.future;
  }

  /// Initialize the settings manager
  Future<void> _initialize() async {
    _logger.info('Initializing settings manager...');
    
    try {
      // Load all settings from storage into cache
      await _loadAllSettings();
      
      // Validate settings and fix any issues
      await _validateAndFixSettings();
      
      _logger.info('Settings manager initialized successfully');
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to initialize settings manager',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Register all default settings definitions
  void _registerDefaultSettings() {
    // General settings
    _registerSetting(SettingDefinition<bool>(
      key: 'general.first_launch',
      category: SettingsCategory.general,
      type: SettingType.boolean,
      defaultValue: true,
      title: 'First Launch',
      description: 'Whether this is the first time launching the app',
    ));

    _registerSetting(SettingDefinition<String>(
      key: 'general.theme',
      category: SettingsCategory.general,
      type: SettingType.enum_,
      defaultValue: 'system',
      title: 'Theme',
      description: 'App theme preference',
      allowedValues: ['light', 'dark', 'system'],
    ));

    _registerSetting(SettingDefinition<String>(
      key: 'general.language',
      category: SettingsCategory.general,
      type: SettingType.enum_,
      defaultValue: 'en',
      title: 'Language',
      description: 'App language',
      allowedValues: ['en', 'es', 'fr', 'de', 'zh'],
      requiresRestart: true,
    ));

    // Voice settings
    _registerSetting(SettingDefinition<bool>(
      key: 'voice.enabled',
      category: SettingsCategory.voice,
      type: SettingType.boolean,
      defaultValue: true,
      title: 'Voice Input Enabled',
      description: 'Enable voice input functionality',
    ));

    _registerSetting(SettingDefinition<double>(
      key: 'voice.sensitivity',
      category: SettingsCategory.voice,
      type: SettingType.double,
      defaultValue: 0.5,
      title: 'Voice Sensitivity',
      description: 'Microphone sensitivity level',
      minValue: 0.0,
      maxValue: 1.0,
    ));

    _registerSetting(SettingDefinition<int>(
      key: 'voice.max_recording_duration',
      category: SettingsCategory.voice,
      type: SettingType.integer,
      defaultValue: 30,
      title: 'Max Recording Duration',
      description: 'Maximum recording duration in seconds',
      minValue: 5,
      maxValue: 300,
    ));

    _registerSetting(SettingDefinition<String>(
      key: 'voice.language',
      category: SettingsCategory.voice,
      type: SettingType.enum_,
      defaultValue: 'en-US',
      title: 'Voice Recognition Language',
      description: 'Language for voice recognition',
      allowedValues: ['en-US', 'en-GB', 'es-ES', 'fr-FR', 'de-DE', 'zh-CN'],
    ));

    // Audio settings
    _registerSetting(SettingDefinition<bool>(
      key: 'audio.tts_enabled',
      category: SettingsCategory.audio,
      type: SettingType.boolean,
      defaultValue: true,
      title: 'Text-to-Speech Enabled',
      description: 'Enable audio responses',
    ));

    _registerSetting(SettingDefinition<double>(
      key: 'audio.tts_speed',
      category: SettingsCategory.audio,
      type: SettingType.double,
      defaultValue: 1.0,
      title: 'Speech Speed',
      description: 'Text-to-speech playback speed',
      minValue: 0.5,
      maxValue: 2.0,
    ));

    _registerSetting(SettingDefinition<double>(
      key: 'audio.tts_pitch',
      category: SettingsCategory.audio,
      type: SettingType.double,
      defaultValue: 1.0,
      title: 'Speech Pitch',
      description: 'Text-to-speech pitch',
      minValue: 0.5,
      maxValue: 2.0,
    ));

    _registerSetting(SettingDefinition<double>(
      key: 'audio.volume',
      category: SettingsCategory.audio,
      type: SettingType.double,
      defaultValue: 0.8,
      title: 'Audio Volume',
      description: 'Default audio volume',
      minValue: 0.0,
      maxValue: 1.0,
    ));

    _registerSetting(SettingDefinition<String>(
      key: 'audio.tts_voice',
      category: SettingsCategory.audio,
      type: SettingType.enum_,
      defaultValue: 'default',
      title: 'TTS Voice',
      description: 'Text-to-speech voice selection',
      allowedValues: ['default', 'male', 'female', 'neural'],
    ));

    // Network settings
    _registerSetting(SettingDefinition<bool>(
      key: 'network.offline_mode',
      category: SettingsCategory.network,
      type: SettingType.boolean,
      defaultValue: false,
      title: 'Offline Mode',
      description: 'Use cached data when possible',
    ));

    _registerSetting(SettingDefinition<int>(
      key: 'network.timeout',
      category: SettingsCategory.network,
      type: SettingType.integer,
      defaultValue: 30,
      title: 'Network Timeout',
      description: 'Network request timeout in seconds',
      minValue: 5,
      maxValue: 120,
    ));

    _registerSetting(SettingDefinition<bool>(
      key: 'network.wifi_only',
      category: SettingsCategory.network,
      type: SettingType.boolean,
      defaultValue: false,
      title: 'WiFi Only',
      description: 'Only use WiFi for network requests',
    ));

    // Privacy settings
    _registerSetting(SettingDefinition<bool>(
      key: 'privacy.analytics_enabled',
      category: SettingsCategory.privacy,
      type: SettingType.boolean,
      defaultValue: false,
      title: 'Analytics Enabled',
      description: 'Allow anonymous usage analytics',
    ));

    _registerSetting(SettingDefinition<bool>(
      key: 'privacy.crash_reporting',
      category: SettingsCategory.privacy,
      type: SettingType.boolean,
      defaultValue: true,
      title: 'Crash Reporting',
      description: 'Send crash reports to help improve the app',
    ));

    _registerSetting(SettingDefinition<int>(
      key: 'privacy.data_retention_days',
      category: SettingsCategory.privacy,
      type: SettingType.integer,
      defaultValue: 30,
      title: 'Data Retention',
      description: 'Days to keep local voice data',
      minValue: 1,
      maxValue: 365,
    ));

    // Accessibility settings
    _registerSetting(SettingDefinition<bool>(
      key: 'accessibility.high_contrast',
      category: SettingsCategory.accessibility,
      type: SettingType.boolean,
      defaultValue: false,
      title: 'High Contrast',
      description: 'Use high contrast colors',
    ));

    _registerSetting(SettingDefinition<double>(
      key: 'accessibility.font_scale',
      category: SettingsCategory.accessibility,
      type: SettingType.double,
      defaultValue: 1.0,
      title: 'Font Scale',
      description: 'Text size multiplier',
      minValue: 0.8,
      maxValue: 2.0,
    ));

    _registerSetting(SettingDefinition<bool>(
      key: 'accessibility.vibration_enabled',
      category: SettingsCategory.accessibility,
      type: SettingType.boolean,
      defaultValue: true,
      title: 'Vibration Feedback',
      description: 'Enable haptic feedback',
    ));

    // Developer settings
    _registerSetting(SettingDefinition<bool>(
      key: 'developer.debug_mode',
      category: SettingsCategory.developer,
      type: SettingType.boolean,
      defaultValue: false,
      title: 'Debug Mode',
      description: 'Enable debug features',
      isAdvanced: true,
    ));

    _registerSetting(SettingDefinition<bool>(
      key: 'developer.verbose_logging',
      category: SettingsCategory.developer,
      type: SettingType.boolean,
      defaultValue: false,
      title: 'Verbose Logging',
      description: 'Enable detailed logging',
      isAdvanced: true,
    ));

    _registerSetting(SettingDefinition<String>(
      key: 'developer.api_endpoint',
      category: SettingsCategory.developer,
      type: SettingType.string,
      defaultValue: 'https://api.lupin.ai',
      title: 'API Endpoint',
      description: 'Custom API endpoint URL',
      isAdvanced: true,
      requiresRestart: true,
    ));
  }

  /// Register a setting definition
  void _registerSetting<T>(SettingDefinition<T> definition) {
    _definitions[definition.key] = definition;
  }

  /// Load all settings from storage
  Future<void> _loadAllSettings() async {
    for (final definition in _definitions.values) {
      final storedValue = _storage.getString('settings.${definition.key}');
      
      if (storedValue != null) {
        try {
          final value = _deserializeValue(storedValue, definition.type);
          _cache[definition.key] = value;
        } catch (error) {
          _logger.warning('Failed to deserialize setting ${definition.key}: $error');
          _cache[definition.key] = definition.defaultValue;
        }
      } else {
        _cache[definition.key] = definition.defaultValue;
      }
    }
  }

  /// Validate and fix any invalid settings
  Future<void> _validateAndFixSettings() async {
    bool hasChanges = false;
    
    for (final definition in _definitions.values) {
      final currentValue = _cache[definition.key];
      
      if (!definition.isValid(currentValue)) {
        _logger.warning('Invalid setting value for ${definition.key}: $currentValue, resetting to default');
        _cache[definition.key] = definition.defaultValue;
        await _persistSetting(definition.key, definition.defaultValue);
        hasChanges = true;
      }
    }
    
    if (hasChanges) {
      _logger.info('Fixed invalid settings');
    }
  }

  /// Get a setting value
  T getSetting<T>(String key) {
    final definition = _definitions[key];
    if (definition == null) {
      throw ArgumentError('Unknown setting: $key');
    }
    
    return _cache[key] as T;
  }

  /// Set a setting value
  Future<void> setSetting<T>(String key, T value) async {
    final definition = _definitions[key] as SettingDefinition<T>?;
    if (definition == null) {
      throw ArgumentError('Unknown setting: $key');
    }
    
    if (!definition.isValid(value)) {
      throw ValidationError.invalid(key, value);
    }
    
    final oldValue = _cache[key];
    _cache[key] = value;
    
    try {
      await _persistSetting(key, value);
      
      // Notify listeners
      _changesController.add(SettingsChangedEvent(
        key: key,
        oldValue: oldValue,
        newValue: value,
        requiresRestart: definition.requiresRestart,
      ));
      
      _logger.debug('Setting updated: $key = $value');
      
    } catch (error) {
      // Rollback cache on persistence failure
      _cache[key] = oldValue;
      _logger.error('Failed to persist setting $key: $error');
      rethrow;
    }
  }

  /// Persist a setting to storage
  Future<void> _persistSetting<T>(String key, T value) async {
    final serializedValue = _serializeValue(value);
    await _storage.setString('settings.$key', serializedValue);
  }

  /// Serialize a value for storage
  String _serializeValue<T>(T value) {
    if (value is String) {
      return value;
    } else if (value is bool || value is int || value is double) {
      return value.toString();
    } else if (value is List || value is Map) {
      return jsonEncode(value);
    } else {
      return value.toString();
    }
  }

  /// Deserialize a value from storage
  dynamic _deserializeValue(String serialized, SettingType type) {
    switch (type) {
      case SettingType.boolean:
        return serialized.toLowerCase() == 'true';
      case SettingType.integer:
        return int.parse(serialized);
      case SettingType.double:
        return double.parse(serialized);
      case SettingType.string:
      case SettingType.enum_:
        return serialized;
      case SettingType.list:
        return jsonDecode(serialized) as List;
      case SettingType.map:
        return jsonDecode(serialized) as Map<String, dynamic>;
    }
  }

  /// Get all settings for a category
  Map<String, dynamic> getSettingsByCategory(SettingsCategory category) {
    final result = <String, dynamic>{};
    
    for (final definition in _definitions.values) {
      if (definition.category == category) {
        result[definition.key] = _cache[definition.key];
      }
    }
    
    return result;
  }

  /// Get all setting definitions for a category
  List<SettingDefinition> getDefinitionsByCategory(SettingsCategory category, {bool includeAdvanced = false}) {
    return _definitions.values
        .where((def) => def.category == category && (includeAdvanced || !def.isAdvanced))
        .toList();
  }

  /// Reset a setting to its default value
  Future<void> resetSetting(String key) async {
    final definition = _definitions[key];
    if (definition == null) {
      throw ArgumentError('Unknown setting: $key');
    }
    
    await setSetting(key, definition.defaultValue);
  }

  /// Reset all settings in a category
  Future<void> resetCategory(SettingsCategory category) async {
    final definitions = _definitions.values.where((def) => def.category == category);
    
    for (final definition in definitions) {
      await resetSetting(definition.key);
    }
  }

  /// Reset all settings to defaults
  Future<void> resetAllSettings() async {
    for (final definition in _definitions.values) {
      await resetSetting(definition.key);
    }
  }

  /// Export settings to JSON
  Map<String, dynamic> exportSettings() {
    final exported = <String, dynamic>{};
    
    for (final definition in _definitions.values) {
      if (!definition.isAdvanced) { // Don't export advanced settings
        exported[definition.key] = _cache[definition.key];
      }
    }
    
    return {
      'version': '1.0',
      'exported_at': DateTime.now().toIso8601String(),
      'settings': exported,
    };
  }

  /// Import settings from JSON
  Future<void> importSettings(Map<String, dynamic> data) async {
    final settings = data['settings'] as Map<String, dynamic>?;
    if (settings == null) {
      throw ArgumentError('Invalid settings data format');
    }
    
    for (final entry in settings.entries) {
      if (_definitions.containsKey(entry.key)) {
        try {
          await setSetting(entry.key, entry.value);
        } catch (error) {
          _logger.warning('Failed to import setting ${entry.key}: $error');
        }
      }
    }
  }

  /// Stream of setting changes
  Stream<SettingsChangedEvent> get onSettingsChanged => _changesController.stream;

  /// Get settings that require app restart
  List<String> getSettingsRequiringRestart() {
    return _definitions.values
        .where((def) => def.requiresRestart)
        .map((def) => def.key)
        .toList();
  }

  /// Check if any changed settings require restart
  bool hasChangesRequiringRestart() {
    // This would track changes since app start in a real implementation
    return false; // Placeholder
  }

  /// Dispose the settings manager
  void dispose() {
    _changesController.close();
  }
}

/// Settings change event
class SettingsChangedEvent {
  final String key;
  final dynamic oldValue;
  final dynamic newValue;
  final bool requiresRestart;

  const SettingsChangedEvent({
    required this.key,
    required this.oldValue,
    required this.newValue,
    required this.requiresRestart,
  });

  @override
  String toString() => 'SettingsChangedEvent(key: $key, oldValue: $oldValue, newValue: $newValue, requiresRestart: $requiresRestart)';
}