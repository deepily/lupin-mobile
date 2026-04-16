import '../../../core/use_cases/base_use_case.dart';
import '../../../core/repositories/interfaces/session_repository.dart';
import '../../../core/repositories/interfaces/user_repository.dart';
import '../../../core/error_handling/error_handler.dart';
import '../../../shared/models/models.dart';

/// Parameters for creating a session
class CreateSessionParams {
  final String userId;
  final String token;
  final Duration? expiresIn;
  final String? deviceId;
  final String? deviceInfo;
  final String? ipAddress;
  final Map<String, dynamic>? metadata;

  const CreateSessionParams({
    required this.userId,
    required this.token,
    this.expiresIn,
    this.deviceId,
    this.deviceInfo,
    this.ipAddress,
    this.metadata,
  });

  @override
  String toString() => 'CreateSessionParams(userId: $userId, deviceId: $deviceId)';
}

/// Use case for creating a new session
class CreateSessionUseCase extends ParameterizedUseCase<Session, CreateSessionParams> {
  final SessionRepository _sessionRepository;
  final UserRepository _userRepository;

  CreateSessionUseCase(
    this._sessionRepository,
    this._userRepository,
  );

  @override
  AppError? validateParams(CreateSessionParams params) {
    if (params.userId.isEmpty) {
      return ValidationError.required('userId');
    }
    if (params.token.isEmpty) {
      return ValidationError.required('token');
    }
    return null;
  }

  @override
  Future<UseCaseResult<Session>> executeInternal(CreateSessionParams params) async {
    try {
      // Validate user exists
      final user = await _userRepository.findById(params.userId);
      if (user == null) {
        return UseCaseResult.failure(
          AuthError(
            'USER_NOT_FOUND',
            'User not found: ${params.userId}',
            userId: params.userId,
            userMessage: 'User account not found.',
          ),
        );
      }

      // Check if user is active
      if (user.status != UserStatus.active) {
        return UseCaseResult.failure(
          AuthError(
            'USER_INACTIVE',
            'User account is not active: ${user.status}',
            userId: params.userId,
            userMessage: 'User account is not active.',
          ),
        );
      }

      // Check for existing active sessions on same device
      if (params.deviceId != null) {
        final existingSessions = await _sessionRepository.findByDevice(params.deviceId!);
        final activeSessions = existingSessions.where(
          (session) => session.status == SessionStatus.active && session.userId == params.userId,
        ).toList();

        if (activeSessions.isNotEmpty) {
          // Terminate existing sessions for this user on this device
          for (final session in activeSessions) {
            await _sessionRepository.terminateSession(session.id);
          }
        }
      }

      // Create new session
      final session = await _sessionRepository.createSession(
        params.userId,
        params.token,
        expiresIn: params.expiresIn,
        deviceId: params.deviceId,
        deviceInfo: params.deviceInfo,
        ipAddress: params.ipAddress,
      );

      // Update session metadata if provided
      if (params.metadata != null) {
        final updatedSession = session.copyWith(
          metadata: {
            ...?session.metadata,
            ...params.metadata!,
            'createdVia': 'mobile_app',
            'userAgent': params.deviceInfo ?? 'unknown',
          },
        );
        await _sessionRepository.update(updatedSession);
        return UseCaseResult.success(updatedSession);
      }

      return UseCaseResult.success(session);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        AuthError(
          'SESSION_CREATION_FAILED',
          'Failed to create session: $error',
          userId: params.userId,
          userMessage: 'Failed to create session. Please try again.',
        ),
      );
    }
  }
}

/// Use case for validating an existing session
class ValidateSessionUseCase extends ParameterizedUseCase<Session, String> {
  final SessionRepository _sessionRepository;

  ValidateSessionUseCase(this._sessionRepository);

  @override
  AppError? validateParams(String sessionId) {
    if (sessionId.isEmpty) {
      return ValidationError.required('sessionId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<Session>> executeInternal(String sessionId) async {
    try {
      // Find session
      final session = await _sessionRepository.findById(sessionId);
      if (session == null) {
        return UseCaseResult.failure(
          AuthError.sessionExpired(sessionId),
        );
      }

      // Check if session is active
      if (session.status != SessionStatus.active) {
        return UseCaseResult.failure(
          AuthError.sessionExpired(sessionId),
        );
      }

      // Check if session is expired
      if (session.expiresAt != null && session.expiresAt!.isBefore(DateTime.now())) {
        // Terminate expired session
        await _sessionRepository.terminateSession(sessionId);
        
        return UseCaseResult.failure(
          AuthError.sessionExpired(sessionId),
        );
      }

      // Update session activity
      final updatedSession = await _sessionRepository.updateActivity(sessionId);

      return UseCaseResult.success(updatedSession);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        AuthError(
          'SESSION_VALIDATION_FAILED',
          'Failed to validate session: $error',
          sessionId: sessionId,
          userMessage: 'Session validation failed. Please sign in again.',
        ),
      );
    }
  }
}

/// Use case for terminating a session
class TerminateSessionUseCase extends ParameterizedUseCase<bool, String> {
  final SessionRepository _sessionRepository;

  TerminateSessionUseCase(this._sessionRepository);

  @override
  AppError? validateParams(String sessionId) {
    if (sessionId.isEmpty) {
      return ValidationError.required('sessionId');
    }
    return null;
  }

  @override
  Future<UseCaseResult<bool>> executeInternal(String sessionId) async {
    try {
      // Check if session exists
      final session = await _sessionRepository.findById(sessionId);
      if (session == null) {
        // Session doesn't exist, consider it already terminated
        return UseCaseResult.success(true);
      }

      // Terminate session
      await _sessionRepository.terminateSession(sessionId);

      return UseCaseResult.success(true);

    } catch (error) {
      if (error is AppError) {
        return UseCaseResult.failure(error);
      }
      
      return UseCaseResult.failure(
        AuthError(
          'SESSION_TERMINATION_FAILED',
          'Failed to terminate session: $error',
          sessionId: sessionId,
          userMessage: 'Failed to sign out. Please try again.',
        ),
      );
    }
  }
}