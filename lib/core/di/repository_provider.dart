import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'service_locator.dart';
import '../repositories/repositories.dart';

/// Provider for easy access to repositories in widgets
class RepositoryProvider extends InheritedWidget {
  final UserRepository userRepository;
  final SessionRepository sessionRepository;
  final JobRepository jobRepository;
  final VoiceRepository voiceRepository;
  final AudioRepository audioRepository;

  const RepositoryProvider({
    super.key,
    required super.child,
    required this.userRepository,
    required this.sessionRepository,
    required this.jobRepository,
    required this.voiceRepository,
    required this.audioRepository,
  });

  static RepositoryProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RepositoryProvider>();
  }

  @override
  bool updateShouldNotify(RepositoryProvider oldWidget) => false;
}

/// Widget that provides repositories to its children
class RepositoryContainer extends StatelessWidget {
  final Widget child;

  const RepositoryContainer({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      userRepository: ServiceLocator.get<UserRepository>(),
      sessionRepository: ServiceLocator.get<SessionRepository>(),
      jobRepository: ServiceLocator.get<JobRepository>(),
      voiceRepository: ServiceLocator.get<VoiceRepository>(),
      audioRepository: ServiceLocator.get<AudioRepository>(),
      child: child,
    );
  }
}

/// Mixin for easy repository access in widgets
mixin RepositoryMixin<T extends StatefulWidget> on State<T> {
  UserRepository get userRepository => ServiceLocator.get<UserRepository>();
  SessionRepository get sessionRepository => ServiceLocator.get<SessionRepository>();
  JobRepository get jobRepository => ServiceLocator.get<JobRepository>();
  VoiceRepository get voiceRepository => ServiceLocator.get<VoiceRepository>();
  AudioRepository get audioRepository => ServiceLocator.get<AudioRepository>();
}

/// Extension for easy repository access in BLoCs
extension RepositoryExtension on BlocBase {
  UserRepository get userRepository => ServiceLocator.get<UserRepository>();
  SessionRepository get sessionRepository => ServiceLocator.get<SessionRepository>();
  JobRepository get jobRepository => ServiceLocator.get<JobRepository>();
  VoiceRepository get voiceRepository => ServiceLocator.get<VoiceRepository>();
  AudioRepository get audioRepository => ServiceLocator.get<AudioRepository>();
}

/// Repository access helper class
class Repositories {
  static UserRepository get user => ServiceLocator.get<UserRepository>();
  static SessionRepository get session => ServiceLocator.get<SessionRepository>();
  static JobRepository get job => ServiceLocator.get<JobRepository>();
  static VoiceRepository get voice => ServiceLocator.get<VoiceRepository>();
  static AudioRepository get audio => ServiceLocator.get<AudioRepository>();
  
  /// Get all repositories as a map
  static Map<String, dynamic> getAll() {
    return {
      'user': user,
      'session': session,
      'job': job,
      'voice': voice,
      'audio': audio,
    };
  }
  
  /// Check if all repositories are available
  static bool get areAvailable {
    try {
      getAll();
      return true;
    } catch (e) {
      return false;
    }
  }
}