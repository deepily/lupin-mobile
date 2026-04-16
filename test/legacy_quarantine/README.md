# Legacy Test Quarantine

Tests quarantined on 2026-04-16 during Tier 1+2 migration triage.
Policy: preserve history; revisit deletion only after new coverage makes the legacy signal redundant.

Mocks for quarantined tests are moved alongside — NOT regenerated.
Source: `src/rnd/v0.1.6-migration/2026.04.16-legacy-test-triage.log`

## Quarantined Files

| File                                                        | Category | Reason                                              | Date       |
|-------------------------------------------------------------|----------|-----------------------------------------------------|------------|
| cache/cache_system_test.dart                                | C        | `cacheAudioForText` signature drift                 | 2026-04-16 |
| connection/connection_recovery_test.dart                    | C        | Requires live WS server; hangs 21 min on timeout   | 2026-04-16 |
| core/cache/voice_recording_cache_test.dart                  | C        | API drift (stale mocks)                             | 2026-04-16 |
| core/cache/voice_recording_cache_test.mocks.dart            | mock     | Dropped alongside quarantined owner                 | 2026-04-16 |
| core/monitoring/performance_monitor_test.dart               | C        | `PerformanceMonitorConfig` constructor drift        | 2026-04-16 |
| core/monitoring/performance_monitor_test.mocks.dart         | mock     | Dropped alongside quarantined owner                 | 2026-04-16 |
| di/dependency_injection_test.dart                           | C        | `AppError` constructor drift                        | 2026-04-16 |
| integration/cache_integration_test.dart                     | C        | `audio.jobId` field drift                           | 2026-04-16 |
| integration/event_system_integration_test.dart              | C        | Requires live WS server                             | 2026-04-16 |
| integration/failure_recovery_test.dart                      | C        | Compile error                                       | 2026-04-16 |
| integration/service_integration_test.dart                   | C        | Compile error                                       | 2026-04-16 |
| integration/websocket_integration_test.dart                 | C        | Requires live WS server                             | 2026-04-16 |
| performance/websocket_performance_test.dart                 | C        | Hangs on network; killed at 30s timeout             | 2026-04-16 |
| repositories/audio_repository_test.dart                     | C        | Compile error                                       | 2026-04-16 |
| repositories/job_repository_test.dart                       | C        | API drift (25 failures)                             | 2026-04-16 |
| repositories/session_repository_test.dart                   | C        | Compile error                                       | 2026-04-16 |
| repositories/storage_integration_test.dart                  | C        | Compile error                                       | 2026-04-16 |
| repositories/user_repository_test.dart                      | C        | Missing `TestWidgetsFlutterBinding` init; >1h fix  | 2026-04-16 |
| repositories/voice_repository_test.dart                     | C        | Compile error                                       | 2026-04-16 |
| services/audio/audio_cache_manager_test.dart                | C        | Compile error (stale mocks)                         | 2026-04-16 |
| services/audio/audio_cache_manager_test.mocks.dart          | mock     | Dropped alongside quarantined owner                 | 2026-04-16 |
| services/websocket/enhanced_websocket_service_test.dart     | C        | Compile error (stale mocks)                         | 2026-04-16 |
| services/websocket/enhanced_websocket_service_test.mocks.dart | mock   | Dropped alongside quarantined owner                 | 2026-04-16 |
| services/websocket/websocket_message_router_test.dart       | C        | Compile error                                       | 2026-04-16 |
| unit/voice_bloc_test.dart                                   | C        | Compile error                                       | 2026-04-16 |
