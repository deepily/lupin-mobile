import '../../../core/use_cases/base_use_case.dart';
import '../../../core/settings/settings_service.dart';
import '../../../core/settings/settings_manager.dart';
import '../../../core/error_handling/error_handler.dart';
import '../../../core/logging/logger.dart';

/// Parameters for updating settings
class UpdateSettingsParams {
  final Map<String, dynamic> settings;
  final bool validateConsistency;

  const UpdateSettingsParams({
    required this.settings,
    this.validateConsistency = true,
  });

  @override
  String toString() => 'UpdateSettingsParams(settings: ${settings.keys}, validateConsistency: $validateConsistency)';
}

/// Use case for updating multiple settings
class UpdateSettingsUseCase extends ParameterizedUseCase<bool, UpdateSettingsParams> {
  final SettingsService _settingsService;

  UpdateSettingsUseCase(this._settingsService);

  @override
  AppError? validateParams(UpdateSettingsParams params) {
    if (params.settings.isEmpty) {
      return ValidationError(
        'EMPTY_SETTINGS',
        'No settings provided to update',
        userMessage: 'No settings to update.',
      );
    }
    return null;
  }

  @override
  Future<UseCaseResult<bool>> executeInternal(UpdateSettingsParams params) async {
    try {
      // Update each setting
      for (final entry in params.settings.entries) {
        await _updateSingleSetting(entry.key, entry.value);
      }

      // Validate consistency if requested
      if (params.validateConsistency) {
        final issues = await _settingsService.validateSettings();
        final errors = issues.where((issue) => issue.type == SettingsValidationIssueType.error);
        
        if (errors.isNotEmpty) {
          return UseCaseResult.failure(
            ValidationError(
              'SETTINGS_CONSISTENCY_ERROR',
              'Settings validation failed: ${errors.first.message}',
              userMessage: errors.first.message,
            ),
          );
        }
      }

      return UseCaseResult.success(true);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        ValidationError(
          'SETTINGS_UPDATE_FAILED',
          'Failed to update settings: $error',
          userMessage: 'Failed to update settings. Please try again.',
        ),
      );
    }
  }

  Future<void> _updateSingleSetting(String key, dynamic value) async {
    // Use the manager directly for type-safe setting updates
    await _settingsService.manager.setSetting(key, value);
  }
}

/// Parameters for applying settings preset
class ApplySettingsPresetParams {
  final QuickSettingsPreset preset;
  final bool backup;

  const ApplySettingsPresetParams({
    required this.preset,
    this.backup = true,
  });

  @override
  String toString() => 'ApplySettingsPresetParams(preset: ${preset.name}, backup: $backup)';
}

/// Use case for applying settings presets
class ApplySettingsPresetUseCase extends ParameterizedUseCase<Map<String, dynamic>, ApplySettingsPresetParams> {
  final SettingsService _settingsService;

  ApplySettingsPresetUseCase(this._settingsService);

  @override
  Future<UseCaseResult<Map<String, dynamic>>> executeInternal(ApplySettingsPresetParams params) async {
    try {
      Map<String, dynamic>? backup;
      
      // Create backup if requested
      if (params.backup) {
        backup = _settingsService.exportSettings();
      }

      // Apply the preset
      await _settingsService.applyQuickPreset(params.preset);

      // Validate the new settings
      final issues = await _settingsService.validateSettings();
      final errors = issues.where((issue) => issue.type == SettingsValidationIssueType.error);
      
      if (errors.isNotEmpty) {
        // Restore backup if there are errors
        if (backup != null) {
          await _settingsService.importSettings(backup);
        }
        
        return UseCaseResult.failure(
          ValidationError(
            'PRESET_VALIDATION_FAILED',
            'Preset validation failed: ${errors.first.message}',
            userMessage: 'Preset could not be applied due to validation errors.',
          ),
        );
      }

      final result = {
        'preset': params.preset.name,
        'backup_created': backup != null,
        'validation_issues': issues.map((issue) => issue.toJson()).toList(),
      };

      return UseCaseResult.success(result);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        ValidationError(
          'PRESET_APPLICATION_FAILED',
          'Failed to apply preset: $error',
          userMessage: 'Failed to apply settings preset. Please try again.',
        ),
      );
    }
  }
}

/// Use case for getting settings by category
class GetSettingsByCategoryUseCase extends ParameterizedUseCase<Map<String, dynamic>, SettingsCategory> {
  final SettingsService _settingsService;

  GetSettingsByCategoryUseCase(this._settingsService);

  @override
  Future<UseCaseResult<Map<String, dynamic>>> executeInternal(SettingsCategory category) async {
    try {
      final settings = _settingsService.manager.getSettingsByCategory(category);
      final definitions = _settingsService.manager.getDefinitionsByCategory(category);
      
      final result = {
        'category': category.name,
        'settings': settings,
        'definitions': definitions.map((def) => def.toJson()).toList(),
      };

      return UseCaseResult.success(result);

    } catch (error) {
      return UseCaseResult.failure(
        ValidationError(
          'GET_SETTINGS_FAILED',
          'Failed to get settings for category: $error',
          userMessage: 'Failed to load settings.',
        ),
      );
    }
  }
}

/// Use case for validating settings
class ValidateSettingsUseCase extends NoParamsUseCase<List<SettingsValidationIssue>> {
  final SettingsService _settingsService;

  ValidateSettingsUseCase(this._settingsService);

  @override
  Future<UseCaseResult<List<SettingsValidationIssue>>> call(NoParams params) async {
    try {
      final issues = await _settingsService.validateSettings();
      return UseCaseResult.success(issues);

    } catch (error) {
      return UseCaseResult.failure(
        ValidationError(
          'SETTINGS_VALIDATION_FAILED',
          'Failed to validate settings: $error',
          userMessage: 'Failed to validate settings.',
        ),
      );
    }
  }
}

/// Parameters for importing settings
class ImportSettingsParams {
  final Map<String, dynamic> settingsData;
  final bool validateAfterImport;
  final bool createBackup;

  const ImportSettingsParams({
    required this.settingsData,
    this.validateAfterImport = true,
    this.createBackup = true,
  });

  @override
  String toString() => 'ImportSettingsParams(validateAfterImport: $validateAfterImport, createBackup: $createBackup)';
}

/// Use case for importing settings
class ImportSettingsUseCase extends ParameterizedUseCase<Map<String, dynamic>, ImportSettingsParams> {
  final SettingsService _settingsService;

  ImportSettingsUseCase(this._settingsService);

  @override
  AppError? validateParams(ImportSettingsParams params) {
    if (params.settingsData.isEmpty) {
      return ValidationError(
        'EMPTY_IMPORT_DATA',
        'No settings data provided for import',
        userMessage: 'No settings data to import.',
      );
    }
    
    // Validate data structure
    if (!params.settingsData.containsKey('settings')) {
      return ValidationError(
        'INVALID_IMPORT_FORMAT',
        'Invalid settings import format',
        userMessage: 'Invalid settings file format.',
      );
    }
    
    return null;
  }

  @override
  Future<UseCaseResult<Map<String, dynamic>>> executeInternal(ImportSettingsParams params) async {
    try {
      Map<String, dynamic>? backup;
      
      // Create backup if requested
      if (params.createBackup) {
        backup = _settingsService.exportSettings();
      }

      // Import settings
      await _settingsService.importSettings(params.settingsData);

      // Validate after import if requested
      List<SettingsValidationIssue> issues = [];
      if (params.validateAfterImport) {
        issues = await _settingsService.validateSettings();
        
        final errors = issues.where((issue) => issue.type == SettingsValidationIssueType.error);
        if (errors.isNotEmpty) {
          // Restore backup if there are critical errors
          if (backup != null) {
            await _settingsService.importSettings(backup);
          }
          
          return UseCaseResult.failure(
            ValidationError(
              'IMPORT_VALIDATION_FAILED',
              'Imported settings validation failed: ${errors.first.message}',
              userMessage: 'Imported settings contain errors and were not applied.',
            ),
          );
        }
      }

      final result = {
        'imported_version': params.settingsData['version'] ?? 'unknown',
        'imported_at': DateTime.now().toIso8601String(),
        'backup_created': backup != null,
        'validation_issues': issues.map((issue) => issue.toJson()).toList(),
      };

      return UseCaseResult.success(result);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        ValidationError(
          'SETTINGS_IMPORT_FAILED',
          'Failed to import settings: $error',
          userMessage: 'Failed to import settings. Please check the file format.',
        ),
      );
    }
  }
}

/// Use case for exporting settings
class ExportSettingsUseCase extends NoParamsUseCase<Map<String, dynamic>> {
  final SettingsService _settingsService;

  ExportSettingsUseCase(this._settingsService);

  @override
  Future<UseCaseResult<Map<String, dynamic>>> call(NoParams params) async {
    try {
      final exportedSettings = _settingsService.exportSettings();
      return UseCaseResult.success(exportedSettings);

    } catch (error) {
      return UseCaseResult.failure(
        ValidationError(
          'SETTINGS_EXPORT_FAILED',
          'Failed to export settings: $error',
          userMessage: 'Failed to export settings.',
        ),
      );
    }
  }
}

/// Use case for resetting settings
class ResetSettingsUseCase extends ParameterizedUseCase<bool, SettingsCategory?> {
  final SettingsService _settingsService;

  ResetSettingsUseCase(this._settingsService);

  @override
  Future<UseCaseResult<bool>> executeInternal(SettingsCategory? category) async {
    try {
      if (category != null) {
        await _settingsService.resetCategory(category);
      } else {
        await _settingsService.resetAllSettings();
      }

      return UseCaseResult.success(true);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        ValidationError(
          'SETTINGS_RESET_FAILED',
          'Failed to reset settings: $error',
          userMessage: 'Failed to reset settings. Please try again.',
        ),
      );
    }
  }
}

/// Stream use case for watching settings changes
class WatchSettingsChangesUseCase extends StreamUseCase<SettingsChangedEvent, NoParams> {
  final SettingsService _settingsService;

  WatchSettingsChangesUseCase(this._settingsService);

  @override
  Stream<UseCaseResult<SettingsChangedEvent>> call(NoParams params) async* {
    try {
      await for (final event in _settingsService.onSettingsChanged) {
        yield UseCaseResult.success(event);
      }
    } catch (error) {
      yield UseCaseResult.failure(
        ValidationError(
          'WATCH_SETTINGS_FAILED',
          'Failed to watch settings changes: $error',
          userMessage: 'Failed to monitor settings changes.',
        ),
      );
    }
  }
}