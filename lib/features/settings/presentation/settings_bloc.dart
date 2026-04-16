import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../../core/settings/settings_service.dart';
import '../../../core/settings/settings_manager.dart';
import '../../../core/logging/logger.dart';
import '../use_cases/settings_use_cases.dart';

// Events
abstract class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object?> get props => [];
}

class LoadSettingsEvent extends SettingsEvent {
  final SettingsCategory? category;

  const LoadSettingsEvent({this.category});

  @override
  List<Object?> get props => [category];
}

class UpdateSettingEvent extends SettingsEvent {
  final String key;
  final dynamic value;

  const UpdateSettingEvent({
    required this.key,
    required this.value,
  });

  @override
  List<Object?> get props => [key, value];
}

class UpdateMultipleSettingsEvent extends SettingsEvent {
  final Map<String, dynamic> settings;

  const UpdateMultipleSettingsEvent({required this.settings});

  @override
  List<Object?> get props => [settings];
}

class ApplyPresetEvent extends SettingsEvent {
  final QuickSettingsPreset preset;

  const ApplyPresetEvent({required this.preset});

  @override
  List<Object?> get props => [preset];
}

class ValidateSettingsEvent extends SettingsEvent {
  const ValidateSettingsEvent();
}

class ImportSettingsEvent extends SettingsEvent {
  final Map<String, dynamic> settingsData;

  const ImportSettingsEvent({required this.settingsData});

  @override
  List<Object?> get props => [settingsData];
}

class ExportSettingsEvent extends SettingsEvent {
  const ExportSettingsEvent();
}

class ResetSettingsEvent extends SettingsEvent {
  final SettingsCategory? category;

  const ResetSettingsEvent({this.category});

  @override
  List<Object?> get props => [category];
}

// States
abstract class SettingsState extends Equatable {
  const SettingsState();

  @override
  List<Object?> get props => [];
}

class SettingsInitial extends SettingsState {
  const SettingsInitial();
}

class SettingsLoading extends SettingsState {
  const SettingsLoading();
}

class SettingsLoaded extends SettingsState {
  final Map<String, dynamic> settings;
  final List<SettingDefinition> definitions;
  final SettingsCategory? category;
  final List<SettingsValidationIssue> validationIssues;

  const SettingsLoaded({
    required this.settings,
    required this.definitions,
    this.category,
    this.validationIssues = const [],
  });

  @override
  List<Object?> get props => [settings, definitions, category, validationIssues];

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

class SettingsUpdated extends SettingsState {
  final String key;
  final dynamic value;
  final bool requiresRestart;

  const SettingsUpdated({
    required this.key,
    required this.value,
    required this.requiresRestart,
  });

  @override
  List<Object?> get props => [key, value, requiresRestart];
}

class SettingsPresetApplied extends SettingsState {
  final QuickSettingsPreset preset;
  final Map<String, dynamic> result;

  const SettingsPresetApplied({
    required this.preset,
    required this.result,
  });

  @override
  List<Object?> get props => [preset, result];
}

class SettingsValidated extends SettingsState {
  final List<SettingsValidationIssue> issues;

  const SettingsValidated({required this.issues});

  @override
  List<Object?> get props => [issues];
}

class SettingsExported extends SettingsState {
  final Map<String, dynamic> exportData;

  const SettingsExported({required this.exportData});

  @override
  List<Object?> get props => [exportData];
}

class SettingsImported extends SettingsState {
  final Map<String, dynamic> result;

  const SettingsImported({required this.result});

  @override
  List<Object?> get props => [result];
}

class SettingsReset extends SettingsState {
  final SettingsCategory? category;

  const SettingsReset({this.category});

  @override
  List<Object?> get props => [category];
}

class SettingsError extends SettingsState {
  final String message;
  final String? errorCode;

  const SettingsError({
    required this.message,
    this.errorCode,
  });

  @override
  List<Object?> get props => [message, errorCode];
}

// BLoC
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