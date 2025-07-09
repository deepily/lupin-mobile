import 'dart:async';
import '../error_handling/error_handler.dart';
import '../logging/logger.dart';

/// Base class for all use cases
abstract class UseCase<Type, Params> {
  final TaggedLogger _logger = Logger.tagged('UseCase');

  /// Execute the use case with parameters
  Future<UseCaseResult<Type>> call(Params params);

  /// Execute the use case with error handling
  Future<UseCaseResult<Type>> execute(Params params) async {
    try {
      _logger.debug('Executing ${runtimeType} with params: $params');
      
      final result = await call(params);
      
      if (result.isSuccess) {
        _logger.debug('${runtimeType} completed successfully');
      } else {
        _logger.warning('${runtimeType} failed: ${result.error}');
      }
      
      return result;
    } catch (error, stackTrace) {
      _logger.error(
        '${runtimeType} threw exception',
        error: error,
        stackTrace: stackTrace,
      );
      
      final appError = error is AppError 
          ? error 
          : AppError('USE_CASE_ERROR', 'Use case execution failed: $error');
      
      return UseCaseResult.failure(appError);
    }
  }
}

/// Use case result wrapper
class UseCaseResult<T> {
  final T? data;
  final AppError? error;
  final bool isSuccess;

  const UseCaseResult._({
    this.data,
    this.error,
    required this.isSuccess,
  });

  /// Create a successful result
  factory UseCaseResult.success(T data) {
    return UseCaseResult._(
      data: data,
      isSuccess: true,
    );
  }

  /// Create a failure result
  factory UseCaseResult.failure(AppError error) {
    return UseCaseResult._(
      error: error,
      isSuccess: false,
    );
  }

  /// Check if the result is a failure
  bool get isFailure => !isSuccess;

  /// Get data or throw if failure
  T get dataOrThrow {
    if (isFailure) {
      throw error!;
    }
    return data!;
  }

  /// Transform the data if successful
  UseCaseResult<R> map<R>(R Function(T data) transform) {
    if (isSuccess) {
      return UseCaseResult.success(transform(data!));
    }
    return UseCaseResult.failure(error!);
  }

  /// Handle both success and failure cases
  R fold<R>(
    R Function(AppError error) onFailure,
    R Function(T data) onSuccess,
  ) {
    if (isSuccess) {
      return onSuccess(data!);
    }
    return onFailure(error!);
  }
}

/// Base class for use cases with no parameters
abstract class NoParamsUseCase<Type> extends UseCase<Type, NoParams> {}

/// Empty parameters class
class NoParams {
  const NoParams();
  
  @override
  String toString() => 'NoParams()';
}

/// Base class for parameterized use cases
abstract class ParameterizedUseCase<Type, Params> extends UseCase<Type, Params> {
  /// Validate parameters before execution
  AppError? validateParams(Params params) => null;

  @override
  Future<UseCaseResult<Type>> call(Params params) async {
    // Validate parameters first
    final validationError = validateParams(params);
    if (validationError != null) {
      return UseCaseResult.failure(validationError);
    }

    return await executeInternal(params);
  }

  /// Internal execution logic (to be implemented by subclasses)
  Future<UseCaseResult<Type>> executeInternal(Params params);
}

/// Stream-based use case for real-time updates
abstract class StreamUseCase<Type, Params> {
  final TaggedLogger _logger = Logger.tagged('StreamUseCase');

  /// Execute the use case and return a stream
  Stream<UseCaseResult<Type>> call(Params params);

  /// Execute with error handling
  Stream<UseCaseResult<Type>> execute(Params params) async* {
    try {
      _logger.debug('Starting stream ${runtimeType} with params: $params');
      
      await for (final result in call(params)) {
        if (result.isFailure) {
          _logger.warning('${runtimeType} stream error: ${result.error}');
        }
        yield result;
      }
      
      _logger.debug('${runtimeType} stream completed');
    } catch (error, stackTrace) {
      _logger.error(
        '${runtimeType} stream threw exception',
        error: error,
        stackTrace: stackTrace,
      );
      
      final appError = error is AppError 
          ? error 
          : AppError('STREAM_USE_CASE_ERROR', 'Stream use case failed: $error');
      
      yield UseCaseResult.failure(appError);
    }
  }
}

/// Use case executor for handling multiple use cases
class UseCaseExecutor {
  static final TaggedLogger _logger = Logger.tagged('UseCaseExecutor');

  /// Execute multiple use cases in parallel
  static Future<List<UseCaseResult<dynamic>>> executeParallel(
    List<Future<UseCaseResult<dynamic>>> useCases,
  ) async {
    _logger.debug('Executing ${useCases.length} use cases in parallel');
    
    try {
      final results = await Future.wait(useCases);
      
      final successCount = results.where((r) => r.isSuccess).length;
      _logger.debug('Parallel execution completed: $successCount/${results.length} successful');
      
      return results;
    } catch (error, stackTrace) {
      _logger.error(
        'Parallel use case execution failed',
        error: error,
        stackTrace: stackTrace,
      );
      
      rethrow;
    }
  }

  /// Execute use cases in sequence
  static Future<List<UseCaseResult<dynamic>>> executeSequential(
    List<Future<UseCaseResult<dynamic>> Function()> useCaseFactories,
  ) async {
    _logger.debug('Executing ${useCaseFactories.length} use cases sequentially');
    
    final results = <UseCaseResult<dynamic>>[];
    
    for (int i = 0; i < useCaseFactories.length; i++) {
      try {
        final result = await useCaseFactories[i]();
        results.add(result);
        
        if (result.isFailure) {
          _logger.warning('Sequential execution stopped at step ${i + 1}: ${result.error}');
          break;
        }
      } catch (error, stackTrace) {
        _logger.error(
          'Sequential execution failed at step ${i + 1}',
          error: error,
          stackTrace: stackTrace,
        );
        
        final appError = AppError(
          'SEQUENTIAL_EXECUTION_ERROR',
          'Sequential execution failed at step ${i + 1}: $error',
        );
        results.add(UseCaseResult.failure(appError));
        break;
      }
    }
    
    _logger.debug('Sequential execution completed with ${results.length} results');
    return results;
  }

  /// Execute use case with retry logic
  static Future<UseCaseResult<T>> executeWithRetry<T>(
    Future<UseCaseResult<T>> Function() useCaseFactory, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
    bool Function(AppError error)? shouldRetry,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (attempt < maxRetries) {
      try {
        final result = await useCaseFactory();
        
        if (result.isSuccess || (shouldRetry != null && !shouldRetry(result.error!))) {
          return result;
        }
        
        attempt++;
        
        if (attempt >= maxRetries) {
          _logger.warning('Use case failed after $attempt attempts: ${result.error}');
          return result;
        }
        
        _logger.debug('Use case failed, retrying in ${delay.inMilliseconds}ms (attempt $attempt/$maxRetries)');
        
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
        
      } catch (error, stackTrace) {
        attempt++;
        
        if (attempt >= maxRetries) {
          _logger.error('Use case retry failed after $attempt attempts', error: error, stackTrace: stackTrace);
          
          final appError = AppError(
            'RETRY_EXECUTION_ERROR',
            'Use case failed after $attempt attempts: $error',
          );
          return UseCaseResult.failure(appError);
        }
        
        _logger.debug('Use case threw exception, retrying in ${delay.inMilliseconds}ms (attempt $attempt/$maxRetries)');
        
        await Future.delayed(delay);
        delay = Duration(milliseconds: (delay.inMilliseconds * backoffMultiplier).round());
      }
    }
    
    throw StateError('Retry loop should not reach this point');
  }
}

/// Use case composition utilities
class UseCaseComposition {
  /// Chain two use cases where the output of the first becomes input to the second
  static Future<UseCaseResult<R>> chain<T, R, P1, P2>(
    UseCase<T, P1> firstUseCase,
    P1 firstParams,
    UseCase<R, P2> secondUseCase,
    P2 Function(T firstResult) secondParamsMapper,
  ) async {
    final firstResult = await firstUseCase.execute(firstParams);
    
    if (firstResult.isFailure) {
      return UseCaseResult.failure(firstResult.error!);
    }
    
    final secondParams = secondParamsMapper(firstResult.data!);
    return await secondUseCase.execute(secondParams);
  }

  /// Combine multiple use case results
  static UseCaseResult<List<T>> combine<T>(List<UseCaseResult<T>> results) {
    final failures = results.where((r) => r.isFailure).toList();
    
    if (failures.isNotEmpty) {
      return UseCaseResult.failure(failures.first.error!);
    }
    
    final data = results.map((r) => r.data!).toList();
    return UseCaseResult.success(data);
  }
}