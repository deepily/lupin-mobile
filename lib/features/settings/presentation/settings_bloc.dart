import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/settings/settings_service.dart';
import '../../../core/settings/settings_manager.dart';
import '../../../core/logging/logger.dart';
import '../use_cases/settings_use_cases.dart';

// Events

/// Base type of everything the settings screens send to [SettingsBloc].
abstract class SettingsEvent extends Equatable {
  /// Creates an event.
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

/// Asks for a category's settings and their validation issues.
class LoadSettingsEvent extends SettingsEvent {
  /// The category to load; null loads the general category.
  final SettingsCategory? category;

  /// Creates the event.
  const LoadSettingsEvent({this.category});

  @override
  List<Object?> get props => [category];
}

/// Sets one setting.
class UpdateSettingEvent extends SettingsEvent {
  /// The setting's key.
  final String key;

  /// The new value.
  final dynamic value;

  /// Creates the event.
  const UpdateSettingEvent({
    required this.key,
    required this.value,
  });

  @override
  List<Object?> get props => [key, value];
}

/// Sets several settings in one call.
class UpdateMultipleSettingsEvent extends SettingsEvent {
  /// The new values, keyed by setting key.
  final Map<String, dynamic> settings;

  /// Creates the event.
  const UpdateMultipleSettingsEvent({required this.settings});

  @override
  List<Object?> get props => [settings];
}

/// Applies a quick-settings preset.
class ApplyPresetEvent extends SettingsEvent {
  /// The preset to apply.
  final QuickSettingsPreset preset;

  /// Creates the event.
  const ApplyPresetEvent({required this.preset});

  @override
  List<Object?> get props => [preset];
}

/// Asks for a validation pass over the stored settings.
class ValidateSettingsEvent extends SettingsEvent {
  /// Creates the event.
  const ValidateSettingsEvent();
}

/// Imports a previously exported set of settings.
class ImportSettingsEvent extends SettingsEvent {
  /// The exported settings data.
  final Map<String, dynamic> settingsData;

  /// Creates the event.
  const ImportSettingsEvent({required this.settingsData});

  @override
  List<Object?> get props => [settingsData];
}

/// Asks for the settings to be exported as data.
class ExportSettingsEvent extends SettingsEvent {
  /// Creates the event.
  const ExportSettingsEvent();
}

/// Resets settings to their defaults.
class ResetSettingsEvent extends SettingsEvent {
  /// The category to reset; null resets everything the use case covers.
  final SettingsCategory? category;

  /// Creates the event.
  const ResetSettingsEvent({this.category});

  @override
  List<Object?> get props => [category];
}

// States

/// Base type of everything [SettingsBloc] emits.
abstract class SettingsState extends Equatable {
  /// Creates a state.
  const SettingsState();

  @override
  List<Object?> get props => [];
}

/// Nothing has been loaded yet.
class SettingsInitial extends SettingsState {
  /// Creates the state.
  const SettingsInitial();
}

/// A load, preset, import or reset is in flight.
class SettingsLoading extends SettingsState {
  /// Creates the state.
  const SettingsLoading();
}

/// A category's settings are loaded and ready to show.
class SettingsLoaded extends SettingsState {
  /// The current values, keyed by setting key.
  final Map<String, dynamic> settings;

  /// The definitions that describe each setting.
  final List<SettingDefinition> definitions;

  /// The category shown; null means the general category.
  final SettingsCategory? category;

  /// Problems the validation pass found.
  final List<SettingsValidationIssue> validationIssues;

  /// Creates the state.
  const SettingsLoaded({
    required this.settings,
    required this.definitions,
    this.category,
    this.validationIssues = const [],
  });

  @override
  List<Object?> get props => [settings, definitions, category, validationIssues];

  /// Returns a copy with any given field replaced.
  SettingsLoaded copyWith({
    Map<String, dynamic>? settings,
    List<SettingDefinition>? definitions,
    SettingsCategory? category,
    List<SettingsValidationIssue>? validationIssues,
  }) {
    return SettingsLoaded(
      settings: settings ?? this.settings,
      definitions: definitions ?? this.definitions,
      category: category ?? this.category,
      validationIssues: validationIssues ?? this.validationIssues,
    );
  }
}

/// One setting was saved.
class SettingsUpdated extends SettingsState {
  /// The setting's key.
  final String key;

  /// The saved value.
  final dynamic value;

  /// Whether the change only takes effect after an app restart.
  final bool requiresRestart;

  /// Creates the state.
  const SettingsUpdated({
    required this.key,
    required this.value,
    required this.requiresRestart,
  });

  @override
  List<Object?> get props => [key, value, requiresRestart];
}

/// A preset was applied.
class SettingsPresetApplied extends SettingsState {
  /// The preset that was applied.
  final QuickSettingsPreset preset;

  /// What the use case reported back.
  final Map<String, dynamic> result;

  /// Creates the state.
  const SettingsPresetApplied({
    required this.preset,
    required this.result,
  });

  @override
  List<Object?> get props => [preset, result];
}

/// A validation pass finished.
class SettingsValidated extends SettingsState {
  /// The problems found; empty when the settings are valid.
  final List<SettingsValidationIssue> issues;

  /// Creates the state.
  const SettingsValidated({required this.issues});

  @override
  List<Object?> get props => [issues];
}

/// The settings were exported.
class SettingsExported extends SettingsState {
  /// The exported settings data.
  final Map<String, dynamic> exportData;

  /// Creates the state.
  const SettingsExported({required this.exportData});

  @override
  List<Object?> get props => [exportData];
}

/// An import finished.
class SettingsImported extends SettingsState {
  /// What the use case reported back.
  final Map<String, dynamic> result;

  /// Creates the state.
  const SettingsImported({required this.result});

  @override
  List<Object?> get props => [result];
}

/// A reset finished.
class SettingsReset extends SettingsState {
  /// The category that was reset; null means everything the use case covers.
  final SettingsCategory? category;

  /// Creates the state.
  const SettingsReset({this.category});

  @override
  List<Object?> get props => [category];
}

/// An operation failed.
class SettingsError extends SettingsState {
  /// A message fit to show the user.
  final String message;

  /// The use case's error code, when it gave one.
  final String? errorCode;

  /// Creates the state.
  const SettingsError({
    required this.message,
    this.errorCode,
  });

  @override
  List<Object?> get props => [message, errorCode];
}

// BLoC

/// Loads, edits, validates, imports, exports and resets settings, and follows live changes.
///
/// After each successful change it reloads the category on screen. It also patches the
/// loaded values whenever the settings service reports a change from elsewhere.
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SettingsService _settingsService;
  final UpdateSettingsUseCase _updateSettingsUseCase;
  final ApplySettingsPresetUseCase _applyPresetUseCase;
  final GetSettingsByCategoryUseCase _getSettingsByCategoryUseCase;
  final ValidateSettingsUseCase _validateSettingsUseCase;
  final ImportSettingsUseCase _importSettingsUseCase;
  final ExportSettingsUseCase _exportSettingsUseCase;
  final ResetSettingsUseCase _resetSettingsUseCase;
  final WatchSettingsChangesUseCase _watchSettingsChangesUseCase;

  final TaggedLogger _logger = Logger.tagged('SettingsBloc');
  StreamSubscription? _settingsChangesSubscription;

  /// Creates the bloc over the settings service and one use case per operation.
  SettingsBloc({
    required SettingsService settingsService,
    required UpdateSettingsUseCase updateSettingsUseCase,
    required ApplySettingsPresetUseCase applyPresetUseCase,
    required GetSettingsByCategoryUseCase getSettingsByCategoryUseCase,
    required ValidateSettingsUseCase validateSettingsUseCase,
    required ImportSettingsUseCase importSettingsUseCase,
    required ExportSettingsUseCase exportSettingsUseCase,
    required ResetSettingsUseCase resetSettingsUseCase,
    required WatchSettingsChangesUseCase watchSettingsChangesUseCase,
  })  : _settingsService = settingsService,
        _updateSettingsUseCase = updateSettingsUseCase,
        _applyPresetUseCase = applyPresetUseCase,
        _getSettingsByCategoryUseCase = getSettingsByCategoryUseCase,
        _validateSettingsUseCase = validateSettingsUseCase,
        _importSettingsUseCase = importSettingsUseCase,
        _exportSettingsUseCase = exportSettingsUseCase,
        _resetSettingsUseCase = resetSettingsUseCase,
        _watchSettingsChangesUseCase = watchSettingsChangesUseCase,
        super(const SettingsInitial()) {
    
    on<LoadSettingsEvent>(_onLoadSettings);
    on<UpdateSettingEvent>(_onUpdateSetting);
    on<UpdateMultipleSettingsEvent>(_onUpdateMultipleSettings);
    on<ApplyPresetEvent>(_onApplyPreset);
    on<ValidateSettingsEvent>(_onValidateSettings);
    on<ImportSettingsEvent>(_onImportSettings);
    on<ExportSettingsEvent>(_onExportSettings);
    on<ResetSettingsEvent>(_onResetSettings);

    // Start watching settings changes
    _startWatchingSettingsChanges();
  }

  Future<void> _onLoadSettings(LoadSettingsEvent event, Emitter<SettingsState> emit) async {
    emit(const SettingsLoading());

    try {
      final result = await _getSettingsByCategoryUseCase.execute(
        event.category ?? SettingsCategory.general,
      );

      if (result.isSuccess) {
        final data = result.data!;
        
        // Also validate settings when loading
        final validationResult = await _validateSettingsUseCase.execute(const NoParams());
        final validationIssues = validationResult.isSuccess ? validationResult.data! : <SettingsValidationIssue>[];

        emit(SettingsLoaded(
          settings: data['settings'] as Map<String, dynamic>,
          definitions: (data['definitions'] as List)
              .map((def) => _parseSettingDefinition(def))
              .toList(),
          category: event.category,
          validationIssues: validationIssues,
        ));
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to load settings',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to load settings', error: error);
      emit(SettingsError(
        message: 'Failed to load settings: $error',
      ));
    }
  }

  Future<void> _onUpdateSetting(UpdateSettingEvent event, Emitter<SettingsState> emit) async {
    try {
      final result = await _updateSettingsUseCase.execute(
        UpdateSettingsParams(settings: {event.key: event.value}),
      );

      if (result.isSuccess) {
        final requiresRestart = _settingsService.getSettingsRequiringRestart().contains(event.key);
        
        emit(SettingsUpdated(
          key: event.key,
          value: event.value,
          requiresRestart: requiresRestart,
        ));

        // Reload current view to show updated values
        if (state is SettingsLoaded) {
          final currentState = state as SettingsLoaded;
          add(LoadSettingsEvent(category: currentState.category));
        }
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to update setting',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to update setting ${event.key}', error: error);
      emit(SettingsError(
        message: 'Failed to update setting: $error',
      ));
    }
  }

  Future<void> _onUpdateMultipleSettings(UpdateMultipleSettingsEvent event, Emitter<SettingsState> emit) async {
    try {
      final result = await _updateSettingsUseCase.execute(
        UpdateSettingsParams(settings: event.settings),
      );

      if (result.isSuccess) {
        emit(const SettingsLoading());
        
        // Reload current view to show updated values
        if (state is SettingsLoaded) {
          final currentState = state as SettingsLoaded;
          add(LoadSettingsEvent(category: currentState.category));
        }
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to update settings',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to update multiple settings', error: error);
      emit(SettingsError(
        message: 'Failed to update settings: $error',
      ));
    }
  }

  Future<void> _onApplyPreset(ApplyPresetEvent event, Emitter<SettingsState> emit) async {
    emit(const SettingsLoading());

    try {
      final result = await _applyPresetUseCase.execute(
        ApplySettingsPresetParams(preset: event.preset),
      );

      if (result.isSuccess) {
        emit(SettingsPresetApplied(
          preset: event.preset,
          result: result.data!,
        ));

        // Reload current view to show updated values
        if (state is SettingsLoaded) {
          final currentState = state as SettingsLoaded;
          add(LoadSettingsEvent(category: currentState.category));
        }
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to apply preset',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to apply preset ${event.preset}', error: error);
      emit(SettingsError(
        message: 'Failed to apply preset: $error',
      ));
    }
  }

  Future<void> _onValidateSettings(ValidateSettingsEvent event, Emitter<SettingsState> emit) async {
    try {
      final result = await _validateSettingsUseCase.execute(const NoParams());

      if (result.isSuccess) {
        emit(SettingsValidated(issues: result.data!));
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to validate settings',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to validate settings', error: error);
      emit(SettingsError(
        message: 'Failed to validate settings: $error',
      ));
    }
  }

  Future<void> _onImportSettings(ImportSettingsEvent event, Emitter<SettingsState> emit) async {
    emit(const SettingsLoading());

    try {
      final result = await _importSettingsUseCase.execute(
        ImportSettingsParams(settingsData: event.settingsData),
      );

      if (result.isSuccess) {
        emit(SettingsImported(result: result.data!));

        // Reload current view to show imported values
        if (state is SettingsLoaded) {
          final currentState = state as SettingsLoaded;
          add(LoadSettingsEvent(category: currentState.category));
        }
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to import settings',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to import settings', error: error);
      emit(SettingsError(
        message: 'Failed to import settings: $error',
      ));
    }
  }

  Future<void> _onExportSettings(ExportSettingsEvent event, Emitter<SettingsState> emit) async {
    try {
      final result = await _exportSettingsUseCase.execute(const NoParams());

      if (result.isSuccess) {
        emit(SettingsExported(exportData: result.data!));
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to export settings',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to export settings', error: error);
      emit(SettingsError(
        message: 'Failed to export settings: $error',
      ));
    }
  }

  Future<void> _onResetSettings(ResetSettingsEvent event, Emitter<SettingsState> emit) async {
    emit(const SettingsLoading());

    try {
      final result = await _resetSettingsUseCase.execute(event.category);

      if (result.isSuccess) {
        emit(SettingsReset(category: event.category));

        // Reload current view to show reset values
        if (state is SettingsLoaded) {
          final currentState = state as SettingsLoaded;
          add(LoadSettingsEvent(category: currentState.category));
        }
      } else {
        emit(SettingsError(
          message: result.error!.userMessage ?? 'Failed to reset settings',
          errorCode: result.error!.code,
        ));
      }
    } catch (error) {
      _logger.error('Failed to reset settings', error: error);
      emit(SettingsError(
        message: 'Failed to reset settings: $error',
      ));
    }
  }

  void _startWatchingSettingsChanges() {
    _settingsChangesSubscription = _watchSettingsChangesUseCase
        .execute(const NoParams())
        .listen(
      (result) {
        if (result.isSuccess) {
          final event = result.data!;
          _logger.debug('Settings changed: ${event.key} = ${event.newValue}');
          
          // Update current state if we're showing settings
          if (state is SettingsLoaded) {
            final currentState = state as SettingsLoaded;
            final updatedSettings = Map<String, dynamic>.from(currentState.settings);
            updatedSettings[event.key] = event.newValue;
            
            emit(currentState.copyWith(settings: updatedSettings));
          }
        }
      },
      onError: (error) {
        _logger.error('Settings changes stream error', error: error);
      },
    );
  }

  SettingDefinition _parseSettingDefinition(Map<String, dynamic> json) {
    // This is a simplified parser - in a real implementation, 
    // you'd need to handle all the different types properly
    return SettingDefinition<dynamic>(
      key: json['key'],
      category: SettingsCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => SettingsCategory.general,
      ),
      type: SettingType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SettingType.string,
      ),
      defaultValue: json['defaultValue'],
      title: json['title'],
      description: json['description'],
      minValue: json['minValue'],
      maxValue: json['maxValue'],
      allowedValues: json['allowedValues']?.cast<dynamic>(),
      requiresRestart: json['requiresRestart'] ?? false,
      isAdvanced: json['isAdvanced'] ?? false,
    );
  }

  @override
  Future<void> close() {
    _settingsChangesSubscription?.cancel();
    return super.close();
  }
}