import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../lib/core/di/service_locator.dart';
import '../../lib/core/di/repository_provider.dart';
import '../../lib/core/app/application.dart';
import '../../lib/core/storage/storage_manager.dart';
import '../../lib/core/cache/cache_exports.dart';
import '../../lib/services/network/cached_http_service.dart';
import '../../lib/services/websocket/websocket_service.dart';
import '../../lib/services/tts/tts_service.dart';
import '../../lib/core/repositories/repositories.dart';
import '../../lib/features/voice/domain/voice_bloc.dart';
import '../../lib/shared/models/models.dart';

void main() {
  group('Dependency Injection Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await ServiceLocator.reset();
    });

    tearDown(() async {
      await ServiceLocator.reset();
    });

    test('ServiceLocator should initialize all dependencies', () async {
      await ServiceLocator.init();

      // Check core services
      expect(ServiceLocator.isRegistered<StorageManager>(), true);
      expect(ServiceLocator.isRegistered<OfflineManager>(), true);
      expect(ServiceLocator.isRegistered<AudioCache>(), true);
      expect(ServiceLocator.isRegistered<NetworkCache>(), true);

      // Check network services
      expect(ServiceLocator.isRegistered<CachedHttpService>(), true);
      expect(ServiceLocator.isRegistered<WebSocketService>(), true);
      expect(ServiceLocator.isRegistered<TtsService>(), true);

      // Check repositories
      expect(ServiceLocator.isRegistered<UserRepository>(), true);
      expect(ServiceLocator.isRegistered<SessionRepository>(), true);
      expect(ServiceLocator.isRegistered<JobRepository>(), true);
      expect(ServiceLocator.isRegistered<VoiceRepository>(), true);
      expect(ServiceLocator.isRegistered<AudioRepository>(), true);

      // Check BLoCs
      expect(ServiceLocator.isRegistered<VoiceBloc>(), true);
    });

    test('ServiceLocator should provide registered services info', () async {
      await ServiceLocator.init();

      final services = ServiceLocator.getRegisteredServices();
      expect(services, isNotEmpty);
      expect(services['StorageManager'], 'Registered');
      expect(services['UserRepository'], 'Registered');
      expect(services['CachedHttpService'], 'Registered');
    });

    test('ServiceLocator should get service instances', () async {
      await ServiceLocator.init();

      // Test getting core services
      final storageManager = ServiceLocator.get<StorageManager>();
      expect(storageManager, isNotNull);

      final offlineManager = ServiceLocator.get<OfflineManager>();
      expect(offlineManager, isNotNull);

      // Test getting repositories
      final userRepo = ServiceLocator.get<UserRepository>();
      expect(userRepo, isNotNull);

      final sessionRepo = ServiceLocator.get<SessionRepository>();
      expect(sessionRepo, isNotNull);

      // Test getting services
      final httpService = ServiceLocator.get<CachedHttpService>();
      expect(httpService, isNotNull);

      final ttsService = ServiceLocator.get<TtsService>();
      expect(ttsService, isNotNull);
    });

    test('ServiceLocator should create new BLoC instances', () async {
      await ServiceLocator.init();

      // Create multiple VoiceBloc instances
      final voiceBloc1 = ServiceLocator.get<VoiceBloc>();
      final voiceBloc2 = ServiceLocator.get<VoiceBloc>();

      expect(voiceBloc1, isNotNull);
      expect(voiceBloc2, isNotNull);
      expect(voiceBloc1, isNot(same(voiceBloc2))); // Should be different instances
    });

    test('ServiceLocator extensions should work', () async {
      await ServiceLocator.init();

      // Test extension methods
      final storageManager = ServiceLocatorExtensions.storageManager;
      expect(storageManager, isNotNull);

      final offlineManager = ServiceLocatorExtensions.offlineManager;
      expect(offlineManager, isNotNull);

      final httpService = ServiceLocatorExtensions.httpService;
      expect(httpService, isNotNull);

      final userRepo = ServiceLocatorExtensions.userRepository;
      expect(userRepo, isNotNull);
    });

    test('Repositories helper should provide easy access', () async {
      await ServiceLocator.init();

      // Test Repositories helper class
      final userRepo = Repositories.user;
      expect(userRepo, isNotNull);

      final sessionRepo = Repositories.session;
      expect(sessionRepo, isNotNull);

      final jobRepo = Repositories.job;
      expect(jobRepo, isNotNull);

      final voiceRepo = Repositories.voice;
      expect(voiceRepo, isNotNull);

      final audioRepo = Repositories.audio;
      expect(audioRepo, isNotNull);

      // Test getAll method
      final allRepos = Repositories.getAll();
      expect(allRepos, hasLength(5));
      expect(allRepos['user'], isNotNull);
      expect(allRepos['session'], isNotNull);

      // Test areAvailable
      expect(Repositories.areAvailable, true);
    });

    test('Application should initialize successfully', () async {
      await Application.initialize();

      expect(Application.isInitialized, true);

      // Check that all services are available
      final storageManager = ServiceLocator.get<StorageManager>();
      expect(storageManager, isNotNull);

      final userRepo = ServiceLocator.get<UserRepository>();
      expect(userRepo, isNotNull);
    });

    test('Application should provide health check', () async {
      await Application.initialize();

      final health = await Application.healthCheck();
      expect(health['initialized'], true);
      expect(health['status'], 'healthy');
      expect(health['storage_keys'], isA<int>());
      expect(health['offline_status'], isA<String>());
    });

    test('Application should provide statistics', () async {
      await Application.initialize();

      final stats = await Application.getStats();
      expect(stats['initialized'], true);
      expect(stats['offline_stats'], isNotNull);
      expect(stats['audio_cache_stats'], isNotNull);
      expect(stats['network_cache_stats'], isNotNull);
      expect(stats['registered_services'], isNotNull);
    });

    test('Dependencies should work together', () async {
      await ServiceLocator.init();

      // Test that dependencies are properly injected
      final userRepo = ServiceLocator.get<UserRepository>();
      final sessionRepo = ServiceLocator.get<SessionRepository>();
      final voiceRepo = ServiceLocator.get<VoiceRepository>();
      final ttsService = ServiceLocator.get<TtsService>();

      // Create a VoiceBloc and verify it has all dependencies
      final voiceBloc = ServiceLocator.get<VoiceBloc>();
      expect(voiceBloc, isNotNull);

      // Test repository operations
      final user = User(
        id: 'user1',
        email: 'test@example.com',
        displayName: 'Test User',
        role: UserRole.user,
        status: UserStatus.active,
        createdAt: DateTime.now(),
      );

      await userRepo.create(user);
      final retrievedUser = await userRepo.findById('user1');
      expect(retrievedUser, isNotNull);
      expect(retrievedUser!.email, 'test@example.com');

      // Test session creation
      final session = await sessionRepo.createSession(
        'user1',
        'token_123',
        expiresIn: Duration(hours: 1),
      );
      expect(session.userId, 'user1');
      expect(session.token, 'token_123');

      // Test voice input creation
      final voiceInput = VoiceInput(
        id: 'voice1',
        sessionId: session.id,
        status: VoiceInputStatus.recording,
        timestamp: DateTime.now(),
      );

      await voiceRepo.create(voiceInput);
      final retrievedVoice = await voiceRepo.findById('voice1');
      expect(retrievedVoice, isNotNull);
      expect(retrievedVoice!.sessionId, session.id);
    });

    test('ServiceLocator should handle reset correctly', () async {
      await ServiceLocator.init();

      // Verify services are registered
      expect(ServiceLocator.isRegistered<StorageManager>(), true);
      expect(ServiceLocator.isRegistered<UserRepository>(), true);

      // Reset and verify services are no longer registered
      await ServiceLocator.reset();
      expect(ServiceLocator.isRegistered<StorageManager>(), false);
      expect(ServiceLocator.isRegistered<UserRepository>(), false);
    });

    test('Application should dispose resources correctly', () async {
      await Application.initialize();
      expect(Application.isInitialized, true);

      await Application.dispose();
      expect(Application.isInitialized, false);
    });

    test('Error handling should work properly', () async {
      // Test getting service before initialization
      expect(() => ServiceLocator.get<StorageManager>(), throwsA(isA<Exception>()));

      // Test getting non-existent service
      await ServiceLocator.init();
      expect(() => ServiceLocator.get<String>(), throwsA(isA<Exception>()));
    });
  });
}