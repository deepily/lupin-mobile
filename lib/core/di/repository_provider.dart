import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'service_locator.dart';
import '../repositories/repositories.dart';

/// Exposes the five repositories to widgets through the widget tree.
///
/// Widgets read it with [RepositoryProvider.of]. It never notifies
/// dependents, because the repositories are fixed for its lifetime.
class RepositoryProvider extends InheritedWidget {
  /// Repository for user accounts.
  final UserRepository userRepository;
  /// Repository for sessions.
  final SessionRepository sessionRepository;
  /// Repository for jobs.
  final JobRepository jobRepository;
  /// Repository for voice requests.
  final VoiceRepository voiceRepository;
  /// Repository for audio data.
  final AudioRepository audioRepository;

  /// Creates a provider that holds the given repositories for [child].
  const RepositoryProvider({
    super.key,
    required super.child,
    required this.userRepository,
    required this.sessionRepository,
    required this.jobRepository,
    required this.voiceRepository,
    required this.audioRepository,
  });

  /// Returns the nearest provider above [context], or null if there is none.
  static RepositoryProvider? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<RepositoryProvider>();
  }

  /// Always false: the held repositories never change.
  @override
  bool updateShouldNotify(RepositoryProvider oldWidget) => false;
}

/// Wraps [child] in a [RepositoryProvider] filled from the service locator.
///
/// Requires:
///   - the repositories are registered in [ServiceLocator]
class RepositoryContainer extends StatelessWidget {
  /// The subtree that receives the repositories.
  final Widget child;

  /// Creates a container around [child].
  const RepositoryContainer({
    super.key,
    required this.child,
  });

  /// Builds the provider with every repository fetched from the locator.
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

/// Gives a widget [State] a getter for each repository from the locator.
mixin RepositoryMixin<T extends StatefulWidget> on State<T> {
  /// The repository for user accounts.
  UserRepository get userRepository => ServiceLocator.get<UserRepository>();
  /// The repository for sessions.
  SessionRepository get sessionRepository => ServiceLocator.get<SessionRepository>();
  /// The repository for jobs.
  JobRepository get jobRepository => ServiceLocator.get<JobRepository>();
  /// The repository for voice requests.
  VoiceRepository get voiceRepository => ServiceLocator.get<VoiceRepository>();
  /// The repository for audio data.
  AudioRepository get audioRepository => ServiceLocator.get<AudioRepository>();
}

/// Gives every bloc a getter for each repository from the locator.
extension RepositoryExtension on BlocBase {
  /// The repository for user accounts.
  UserRepository get userRepository => ServiceLocator.get<UserRepository>();
  /// The repository for sessions.
  SessionRepository get sessionRepository => ServiceLocator.get<SessionRepository>();
  /// The repository for jobs.
  JobRepository get jobRepository => ServiceLocator.get<JobRepository>();
  /// The repository for voice requests.
  VoiceRepository get voiceRepository => ServiceLocator.get<VoiceRepository>();
  /// The repository for audio data.
  AudioRepository get audioRepository => ServiceLocator.get<AudioRepository>();
}

/// Static shortcuts to the repositories held by the service locator.
class Repositories {
  /// The repository for user accounts.
  static UserRepository get user => ServiceLocator.get<UserRepository>();
  /// The repository for sessions.
  static SessionRepository get session => ServiceLocator.get<SessionRepository>();
  /// The repository for jobs.
  static JobRepository get job => ServiceLocator.get<JobRepository>();
  /// The repository for voice requests.
  static VoiceRepository get voice => ServiceLocator.get<VoiceRepository>();
  /// The repository for audio data.
  static AudioRepository get audio => ServiceLocator.get<AudioRepository>();
  
  /// Returns every repository in a map keyed by short name.
  static Map<String, dynamic> getAll() {
    return {
      'user': user,
      'session': session,
      'job': job,
      'voice': voice,
      'audio': audio,
    };
  }
  
  /// True when every repository can be fetched from the locator.
  static bool get areAvailable {
    try {
      getAll();
      return true;
    } catch (e) {
      return false;
    }
  }
}