// Row 1b192f22 follow-up (Pocholo, Probe 3): when the app starts paused, initialize() must run the pause
// bookkeeping: usage state background, no inactivity timer, and the log flush a pause normally starts.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/lifecycle/app_lifecycle_service.dart';

class _CountingDestination implements LogDestination {
  int flushCalls = 0;

  @override
  void write( LogEntry entry ) {}

  @override
  Future<void> flush() async => flushCalls++;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // The service is a process-wide singleton; this file starts it once, paused.
  test( "starting while paused gives the background usage state, no inactivity timer and a log flush", () {
    Logger.resetForTesting();
    addTearDown( Logger.resetForTesting );
    final counting = _CountingDestination();
    Logger.addDestination( counting );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );

    final service = AppLifecycleService();

    // initialize() runs inside the fake clock, so its timers are the ones the elapse below advances.
    fakeAsync( ( async ) {
      service.initialize();
      async.flushMicrotasks();

      expect( service.currentLifecycleState, AppLifecycleState.paused );
      expect( service.currentUsageState, AppUsageState.background );
      expect( counting.flushCalls, 1, reason: "the pause handler flushes logs" );

      // Five times the threshold: a live inactivity timer would have flipped the state to inactive.
      async.elapse( AppLifecycleService.inactivityThreshold * 5 );
      expect( service.currentUsageState, AppUsageState.background );
    } );
  } );
}
