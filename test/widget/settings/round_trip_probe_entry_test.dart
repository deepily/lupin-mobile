import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_audio_settings_screen.dart';
import 'package:lupin_mobile/features/settings/presentation/round_trip_probe_screen.dart';
import 'package:lupin_mobile/services/diagnostics/round_trip_probe.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

void main() {
  group( 'Debug section: network round-trip probe entry', () {
    late NotificationPreferences prefs;
    late Dio                     dio;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      prefs = NotificationPreferences( await SharedPreferences.getInstance() );
      dio   = Dio();
      GetIt.instance.registerSingleton<Dio>( dio );
    } );

    tearDown( () async {
      await GetIt.instance.reset();
    } );

    testWidgets( 'settings shows a Debug entry that opens the probe screen on the shared Dio', ( tester ) async {
      await tester.pumpWidget( MaterialApp( home: NotificationAudioSettingsScreen( prefs: prefs ) ) );
      await tester.pump();

      final entry = find.byKey( const Key( TestKeys.settingsOpenRoundTripProbe ) );
      await tester.dragUntilVisible( entry, find.byType( ListView ), const Offset( 0, -200 ) );
      await tester.pump();

      expect( entry, findsOneWidget );
      expect( find.text( 'Network round-trip probe' ), findsOneWidget );
      expect( find.text( 'Debug' ), findsOneWidget );
      expect( tester.widget<ListTile>( entry ).enabled, isTrue );

      await tester.tap( entry );
      await tester.pumpAndSettle();

      expect( find.byType( RoundTripProbeScreen ), findsOneWidget );
      expect( tester.widget<RoundTripProbeScreen>( find.byType( RoundTripProbeScreen ) ).dio, same( dio ) );
      expect( find.byKey( const Key( TestKeys.probeRunButton ) ), findsOneWidget );
      // Nothing runs until the user asks.
      expect( find.byKey( const Key( TestKeys.probeProgress ) ), findsNothing );
    } );
  } );

  testWidgets( 'probe screen runs on a mocked adapter and shows the summary and log path', ( tester ) async {
    final dio  = Dio( BaseOptions( baseUrl: 'http://probe.test' ) )..httpClientAdapter = _OkAdapter();
    final sink = _MemorySink();
    await tester.pumpWidget( MaterialApp(
      home: RoundTripProbeScreen(
        dio         : dio,
        openSink    : ( _ ) async => sink,
        networkType : () async => 'wifi',
      ),
    ) );

    await tester.tap( find.byKey( const Key( TestKeys.probeRunButton ) ) );
    // The probe mixes real async (clip generation, stream drains) with the
    // test zone, so alternate real waits with pumps until the run finishes.
    for ( var i = 0; i < 400 && find.text( 'health' ).evaluate().isEmpty; i++ ) {
      await tester.runAsync( () => Future<void>.delayed( const Duration( milliseconds: 10 ) ) );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect( sink.lines.length, 26 );
    expect( find.text( 'health' ), findsOneWidget );
    expect( find.text( 'upload 44.1 kHz' ), findsOneWidget );
    expect( find.text( 'upload 16 kHz' ), findsOneWidget );
    expect( find.text( 'Log: ${sink.path}' ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.probeCopyPathButton ) ), findsOneWidget );
  } );
}

class _OkAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch( RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture ) async {
    if ( requestStream != null ) await requestStream.drain<void>();
    return ResponseBody.fromString( '"ok"', 200,
        headers: { Headers.contentTypeHeader: [ Headers.jsonContentType ] } );
  }

  @override
  void close( { bool force = false } ) {}
}

class _MemorySink implements ProbeSink {
  final List<String> lines = [];
  @override
  String get path => '/memory/round-trip-probe-widget.jsonl';
  @override
  Future<void> writeLine( String line ) async => lines.add( line );
  @override
  Future<void> close() async {}
}
