/// Examples of how to use the dependency injection system
/// This file demonstrates various patterns for accessing services and repositories

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'service_locator.dart';
import 'repository_provider.dart';
import '../repositories/repositories.dart';
import '../cache/cache_exports.dart';
import '../../services/tts/tts_service.dart';
import '../../shared/models/models.dart';

/// Example 1: Basic service access in a widget
class BasicServiceExample extends StatelessWidget {
  const BasicServiceExample({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadUserData(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return Text('User: ${snapshot.data!['name']}');
        }
        return const CircularProgressIndicator();
      },
    );
  }

  Future<Map<String, dynamic>> _loadUserData() async {
    // Access repository directly through ServiceLocator
    final userRepository = ServiceLocator.get<UserRepository>();
    final user = await userRepository.findById('current_user');
    
    return {
      'name': user?.displayName ?? 'Unknown',
      'email': user?.email ?? 'No email',
    };
  }
}

/// Example 2: Using repository mixin in a stateful widget
class RepositoryMixinExample extends StatefulWidget {
  const RepositoryMixinExample({super.key});

  @override
  State<RepositoryMixinExample> createState() => _RepositoryMixinExampleState();
}

class _RepositoryMixinExampleState extends State<RepositoryMixinExample> 
    with RepositoryMixin {
  List<VoiceInput> _recentVoices = [];

  @override
  void initState() {
    super.initState();
    _loadRecentVoices();
  }

  Future<void> _loadRecentVoices() async {
    // Access repository through mixin
    final voices = await voiceRepository.findAll();
    setState(() {
      _recentVoices = voices.take(5).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _recentVoices.length,
      itemBuilder: (context, index) {
        final voice = _recentVoices[index];
        return ListTile(
          title: Text(voice.transcription ?? 'No transcription'),
          subtitle: Text(voice.timestamp.toString()),
        );
      },
    );
  }
}

/// Example 3: Using Repositories helper class
class RepositoriesHelperExample extends StatelessWidget {
  const RepositoriesHelperExample({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _getDataCounts(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final counts = snapshot.data!;
          return Column(
            children: [
              Text('Users: ${counts['users']}'),
              Text('Sessions: ${counts['sessions']}'),
              Text('Jobs: ${counts['jobs']}'),
              Text('Voice Inputs: ${counts['voices']}'),
            ],
          );
        }
        return const CircularProgressIndicator();
      },
    );
  }

  Future<Map<String, int>> _getDataCounts() async {
    // Use Repositories helper for clean access
    return {
      'users': await Repositories.user.count(),
      'sessions': await Repositories.session.count(),
      'jobs': await Repositories.job.count(),
      'voices': await Repositories.voice.count(),
    };
  }
}

/// Example 4: BLoC with dependency injection
class UserManagementBloc extends Bloc<UserManagementEvent, UserManagementState> {
  final UserRepository _userRepository;
  final SessionRepository _sessionRepository;
  final OfflineManager _offlineManager;

  UserManagementBloc({
    required UserRepository userRepository,
    required SessionRepository sessionRepository,
    required OfflineManager offlineManager,
  })  : _userRepository = userRepository,
        _sessionRepository = sessionRepository,
        _offlineManager = offlineManager,
        super(UserManagementInitial()) {
    on<LoadUserEvent>(_onLoadUser);
    on<CreateSessionEvent>(_onCreateSession);
  }

  // Factory constructor using ServiceLocator
  factory UserManagementBloc.create() {
    return UserManagementBloc(
      userRepository: ServiceLocator.get<UserRepository>(),
      sessionRepository: ServiceLocator.get<SessionRepository>(),
      offlineManager: ServiceLocator.get<OfflineManager>(),
    );
  }

  Future<void> _onLoadUser(LoadUserEvent event, Emitter<UserManagementState> emit) async {
    try {
      emit(UserManagementLoading());
      
      final user = await _userRepository.findById(event.userId);
      if (user != null) {
        emit(UserManagementLoaded(user));
      } else {
        emit(UserManagementError('User not found'));
      }
    } catch (e) {
      emit(UserManagementError(e.toString()));
    }
  }

  Future<void> _onCreateSession(CreateSessionEvent event, Emitter<UserManagementState> emit) async {
    try {
      final session = await _sessionRepository.createSession(
        event.userId,
        event.token,
        expiresIn: Duration(hours: 24),
      );
      
      // Cache session for offline use
      await _offlineManager.cacheForOffline(
        'user_sessions',
        session.id,
        session,
        toJson: (s) => s.toJson(),
        fromJson: (json) => Session.fromJson(json),
      );
      
      emit(SessionCreated(session));
    } catch (e) {
      emit(UserManagementError(e.toString()));
    }
  }
}

/// Example 5: Service integration
class TtsIntegrationExample extends StatelessWidget {
  const TtsIntegrationExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () => _testTtsWithCaching(),
          child: const Text('Test TTS with Caching'),
        ),
        ElevatedButton(
          onPressed: () => _testOfflineCapabilities(),
          child: const Text('Test Offline Capabilities'),
        ),
      ],
    );
  }

  Future<void> _testTtsWithCaching() async {
    final ttsService = ServiceLocator.get<TtsService>();
    final audioCache = ServiceLocator.get<AudioCache>();
    
    const text = 'Hello, this is a test message';
    const provider = 'elevenlabs';
    
    // Check if audio is cached
    final cachedAudio = await audioCache.getCachedAudioForText(text, provider);
    
    if (cachedAudio != null) {
      print('Using cached audio with ${cachedAudio.length} chunks');
    } else {
      print('Generating new audio...');
      // This would normally generate TTS audio
      // final audioChunks = await ttsService.generateAudio(text, provider);
      // await audioCache.cacheAudioForText(text, provider, audioChunks);
    }
  }

  Future<void> _testOfflineCapabilities() async {
    final offlineManager = ServiceLocator.get<OfflineManager>();
    
    if (offlineManager.isOffline) {
      print('Device is offline');
      
      // Queue a request for when online
      await offlineManager.queueRequest('test_request', {
        'action': 'sync_data',
        'timestamp': DateTime.now().toIso8601String(),
      });
      
      // Get cached data
      final cachedUser = await offlineManager.getCachedData<User>(
        'users',
        'current_user',
        toJson: (user) => user.toJson(),
        fromJson: (json) => User.fromJson(json),
      );
      
      if (cachedUser != null) {
        print('Using cached user: ${cachedUser.email}');
      }
    } else {
      print('Device is online');
      
      // Process any queued requests
      await offlineManager.processQueuedRequests();
    }
  }
}

/// Example 6: Cache management
class CacheManagementExample extends StatelessWidget {
  const CacheManagementExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () => _showCacheStats(),
          child: const Text('Show Cache Statistics'),
        ),
        ElevatedButton(
          onPressed: () => _clearAllCaches(),
          child: const Text('Clear All Caches'),
        ),
      ],
    );
  }

  Future<void> _showCacheStats() async {
    final audioCache = ServiceLocator.get<AudioCache>();
    final networkCache = ServiceLocator.get<NetworkCache>();
    final offlineManager = ServiceLocator.get<OfflineManager>();
    
    final audioStats = await audioCache.getStats();
    final networkStats = await networkCache.getStats();
    final offlineStats = await offlineManager.getOfflineStats();
    
    print('Audio Cache: ${audioStats.totalChunks} chunks, ${audioStats.totalSizeBytes} bytes');
    print('Network Cache: ${networkStats.totalResponses} responses, ${networkStats.hitRate}% hit rate');
    print('Offline: ${offlineStats.totalCachedItems} items, ${offlineStats.queuedRequestCount} queued');
  }

  Future<void> _clearAllCaches() async {
    final audioCache = ServiceLocator.get<AudioCache>();
    final networkCache = ServiceLocator.get<NetworkCache>();
    final offlineManager = ServiceLocator.get<OfflineManager>();
    
    await audioCache.clearAll();
    await networkCache.clearAll();
    await offlineManager.clearOfflineData();
    
    print('All caches cleared');
  }
}

// BLoC events and states for the example
abstract class UserManagementEvent {}

class LoadUserEvent extends UserManagementEvent {
  final String userId;
  LoadUserEvent(this.userId);
}

class CreateSessionEvent extends UserManagementEvent {
  final String userId;
  final String token;
  CreateSessionEvent(this.userId, this.token);
}

abstract class UserManagementState {}

class UserManagementInitial extends UserManagementState {}

class UserManagementLoading extends UserManagementState {}

class UserManagementLoaded extends UserManagementState {
  final User user;
  UserManagementLoaded(this.user);
}

class SessionCreated extends UserManagementState {
  final Session session;
  SessionCreated(this.session);
}

class UserManagementError extends UserManagementState {
  final String message;
  UserManagementError(this.message);
}