/// Fold-later from the 597c5dc review (row 8d9b2a0c): `ServerContextToggle`
/// subscribed to its service in `initState` and unsubscribed in `dispose`, but
/// never reacted to being handed a DIFFERENT service. Flutter reuses the State
/// across such a rebuild, so the widget stayed wired to the old service — the
/// new one's switches never redrew the segments, and the old one kept calling
/// a listener nobody was watching.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/presentation/server_context_toggle.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';

void main() {
  final shippedJson = File( "assets/config/server-contexts.json" ).readAsStringSync();

  setUp( () => SharedPreferences.setMockInitialValues( {} ) );

  Future<ServerContextService> loadService( WidgetTester tester ) async {
    tester.binding.defaultBinaryMessenger.setMockMessageHandler( "flutter/assets", ( message ) async {
      final key = const StringCodec().decodeMessage( message );
      return key == "assets/config/server-contexts.json"
        ? const StringCodec().encodeMessage( shippedJson )
        : null;
    } );
    return ( await tester.runAsync( () async =>
      ServerContextService.load( await SharedPreferences.getInstance() ) ) )!;
  }

  Future<void> pumpWith( WidgetTester tester, ServerContextService service ) =>
    tester.pumpWidget( MaterialApp(
      home: Scaffold( body: ServerContextToggle( service: service ) ),
    ) );

  Set<String> selection( WidgetTester tester ) => tester.widget<SegmentedButton<String>>(
    find.byKey( const Key( TestKeys.serverContextToggle ) ) ).selected;

  testWidgets( "handed a new service, the toggle follows the NEW one's switches", ( tester ) async {
    final first  = await loadService( tester );
    final second = await loadService( tester );

    await pumpWith( tester, first );
    expect( selection( tester ), { "dev" }, reason: "both services start on the shipped default" );

    // Same widget type at the same position: Flutter keeps the State and calls
    // didUpdateWidget rather than initState.
    await pumpWith( tester, second );

    await second.setActive( "lan-dev" );
    await tester.pump();

    expect( selection( tester ), { "lan-dev" } );
    expect( find.text( "LAN DEV · http://192.168.1.21:7999" ), findsOneWidget );
  } );

  testWidgets( "handed a new service, the toggle ignores the OLD one's switches", ( tester ) async {
    final first  = await loadService( tester );
    final second = await loadService( tester );

    await pumpWith( tester, first );
    await pumpWith( tester, second );

    await first.setActive( "lan-test" );
    await tester.pump();

    expect( selection( tester ), { "dev" }, reason: "the old service is no longer listened to" );
    expect( find.text( "LAN TEST · http://192.168.1.21:8000" ), findsNothing );
  } );

  testWidgets( "a new service already on another context is adopted, not re-read from the old one", ( tester ) async {
    final first  = await loadService( tester );
    final second = await loadService( tester );
    await second.setActive( "lan-test" );

    await pumpWith( tester, first );
    await pumpWith( tester, second );
    await tester.pump();

    expect( selection( tester ), { "lan-test" } );
  } );
}
