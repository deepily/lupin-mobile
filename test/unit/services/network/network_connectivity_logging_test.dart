// NetworkConnectivityService logs its two real failures through the app Logger.
// The expected "internet test failed while offline" lines stay debugPrint and are not asserted here.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/network/network_connectivity_service.dart';

class _Capture implements LogDestination {
  final List<LogEntry> entries = [];

  @override
  void write( LogEntry entry ) => entries.add( entry );

  @override
  Future<void> flush() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test( "initial connectivity failure and a subscription error each log one error entry", () async {
    Logger.resetForTesting();
    final capture   = _Capture();
    Logger.addDestination( capture );
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel( "dev.fluttercommunity.plus/connectivity" ),
      ( _ ) async => throw PlatformException( code: "unavailable", message: "no connectivity service" ),
    );
    messenger.setMockStreamHandler(
      const EventChannel( "dev.fluttercommunity.plus/connectivity_status" ),
      MockStreamHandler.inline( onListen: ( _, sink ) => sink.error( code: "stream", message: "stream broke" ) ),
    );
    final service = NetworkConnectivityService();

    await service.initialize();
    await Future<void>.delayed( const Duration( milliseconds: 100 ) );

    final errors = capture.entries.where( ( e ) => e.tag == "NetworkService" && e.level == LogLevel.error ).toList();
    expect( errors.map( ( e ) => e.message ), containsAll( [ "Error getting initial connectivity", "Connectivity subscription error" ] ) );
    expect( errors, hasLength( 2 ) );
    expect( errors.every( ( e ) => e.error != null ), isTrue );
    expect( errors.firstWhere( ( e ) => e.message == "Error getting initial connectivity" ).stackTrace, isNotNull );

    service.dispose();
    Logger.resetForTesting();
  } );
}
