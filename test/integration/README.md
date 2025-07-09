# Integration Test Suite

This directory contains comprehensive integration tests that verify the interaction between different services and components in the Lupin Mobile application.

## Test Categories

### 1. Service Integration Tests (`service_integration_test.dart`)
Tests the integration between core services and repositories:

- **HTTP Service Integration**: Authentication with sessions, response caching, session expiration handling
- **WebSocket Service Integration**: Real-time voice updates, job status synchronization, audio streaming
- **TTS Service Integration**: Audio repository caching, queue management, pipeline coordination
- **Cross-Service Data Flow**: Complete voice-to-audio pipeline, error propagation, concurrent operations
- **Performance Testing**: High-volume operations, cache performance, load testing

**Key Features Tested:**
- Session management across HTTP and WebSocket services
- Voice input lifecycle from recording to TTS output
- Real-time data synchronization
- Error handling and recovery
- Concurrent operation handling

### 2. WebSocket Integration Tests (`websocket_integration_test.dart`)
Focuses on real-time communication and data synchronization:

- **Voice Processing**: Real-time status updates, streaming transcription updates
- **Job Queue Management**: Priority-based processing, concurrent job handling
- **Audio Streaming**: Multi-stream management, playback state synchronization
- **Session Management**: Multi-user sessions, activity tracking
- **Error Handling**: Connection failures, partial synchronization, recovery

**Key Features Tested:**
- Real-time voice input processing pipeline
- WebSocket message handling and routing
- Job queue priority management
- Audio streaming coordination
- Connection failure recovery

### 3. Cache Integration Tests (`cache_integration_test.dart`)
Tests caching strategies and data persistence:

- **HTTP Response Caching**: TTL-based expiration, cache consistency
- **Audio Data Caching**: Disk persistence, size limits, TTS pipeline integration
- **Session Caching**: Memory-only caching, invalidation strategies
- **Cache Coordination**: Cross-service consistency, eviction policies
- **Performance Optimization**: Cache hit rates, concurrent operations

**Key Features Tested:**
- Multi-level caching (memory, disk, hybrid)
- Cache eviction and cleanup strategies
- Data consistency across cache layers
- Performance benefits and optimization
- Cache coordination with repositories

## Test Execution

### Running Individual Test Suites
```bash
# Run service integration tests
flutter test test/integration/service_integration_test.dart

# Run WebSocket integration tests
flutter test test/integration/websocket_integration_test.dart

# Run cache integration tests
flutter test test/integration/cache_integration_test.dart
```

### Running Complete Integration Suite
```bash
# Run all integration tests
flutter test test/integration/integration_test_runner.dart

# Run with verbose output
flutter test test/integration/integration_test_runner.dart --verbose

# Run with coverage
flutter test test/integration/integration_test_runner.dart --coverage
```

## Test Architecture

### Dependencies
The integration tests rely on:
- **Flutter Test Framework**: Core testing infrastructure
- **SharedPreferences Mock**: Local storage simulation
- **Repository Implementations**: Data layer testing
- **Service Implementations**: Network and business logic testing
- **Cache Managers**: Multi-level caching testing

### Test Data Management
- **Mock Data**: Generated test data for consistent testing
- **Shared Setup**: Common initialization across test suites
- **Cleanup**: Proper teardown to prevent test interference
- **Isolation**: Each test group operates independently

### Performance Benchmarks
The tests include performance validation with these thresholds:
- Session creation: < 100ms
- Voice processing: < 2 seconds
- Cache operations: < 50ms
- WebSocket responses: < 500ms
- End-to-end scenarios: < 5 seconds

## Test Scenarios

### Complete User Interaction Flow
1. **Session Creation**: User authenticates and session is created
2. **Voice Input**: User speaks, voice recording begins
3. **Real-time Processing**: Voice is transcribed via WebSocket updates
4. **Response Generation**: AI response is generated and queued for TTS
5. **Audio Generation**: TTS service generates audio output
6. **Audio Caching**: Generated audio is cached for performance
7. **Playback**: Audio is played back to user
8. **Session Management**: Session activity is tracked and maintained

### Error Scenarios
- **Network Failures**: WebSocket disconnections, HTTP timeouts
- **Service Failures**: TTS service unavailable, transcription errors
- **Data Inconsistency**: Partial updates, synchronization issues
- **Resource Constraints**: Memory limits, cache eviction, concurrent limits

### Concurrent Operations
- **Multi-user Sessions**: Multiple users with simultaneous voice inputs
- **Parallel Processing**: Concurrent TTS generation and audio streaming
- **Cache Coordination**: Simultaneous cache operations across services
- **Resource Sharing**: Shared repositories and network connections

## Metrics and Reporting

### Test Metrics Tracked
- **Success Rate**: Percentage of tests passing
- **Execution Time**: Total and per-test execution duration
- **Cache Performance**: Hit rates, eviction counts, memory usage
- **WebSocket Events**: Message throughput, latency, connection stability
- **Data Consistency**: Synchronization accuracy across services

### Performance Profiling
The tests include performance profiling for:
- Memory usage patterns
- CPU utilization during operations
- Network bandwidth usage
- Disk I/O for cache operations
- Garbage collection impact

## Configuration

### Test Configuration (`IntegrationTestConfig`)
```dart
static const Duration defaultTimeout = Duration(seconds: 30);
static const int maxConcurrentOperations = 10;
static const int performanceIterations = 100;
```

### Environment Variables
- `LUPIN_TEST_MODE`: Enable test-specific behavior
- `LUPIN_MOCK_SERVICES`: Use mock implementations
- `LUPIN_PERFORMANCE_TESTS`: Enable performance benchmarking

### Mock Configuration
- **WebSocket**: Mock server for real-time testing
- **HTTP**: Mock API responses and error conditions
- **TTS**: Mock audio generation for testing
- **Storage**: In-memory storage for test isolation

## Debugging and Troubleshooting

### Common Issues
1. **Test Timeouts**: Increase timeout values for slow operations
2. **Mock Data**: Ensure consistent test data generation
3. **Async Operations**: Proper waiting for async operations to complete
4. **Resource Cleanup**: Verify proper disposal of resources

### Debug Mode
Enable verbose logging in tests:
```dart
setUp(() async {
  // Enable debug logging
  Logger.level = Level.DEBUG;
  SharedPreferences.setMockInitialValues({});
});
```

### Performance Debugging
For performance issues:
1. Check cache hit rates
2. Monitor memory usage
3. Profile async operation timing
4. Validate concurrent operation limits

## Future Enhancements

### Planned Test Additions
- **End-to-End UI Tests**: Full user interface testing
- **Load Testing**: High-volume concurrent user simulation
- **Security Testing**: Authentication and data protection validation
- **Offline Testing**: Offline mode and synchronization testing

### Test Automation
- **CI/CD Integration**: Automated test execution on commits
- **Performance Regression**: Automated performance monitoring
- **Test Report Generation**: Detailed HTML test reports
- **Code Coverage**: Integration with coverage reporting tools

## Contributing

When adding new integration tests:
1. Follow existing test structure and naming conventions
2. Include proper setup and teardown
3. Add performance benchmarks for new features
4. Update this documentation with new test descriptions
5. Ensure tests are isolated and repeatable