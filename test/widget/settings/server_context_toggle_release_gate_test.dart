/// Fold-later from the 597c5dc review (row 8d9b2a0c): the server switch is a
/// development affordance and should not ship. It now defaults to
/// `!kReleaseMode` — debug and profile keep it, release gets nothing.
///
/// `kReleaseMode` is a compile-time constant, so a test can never observe the
/// release arm through it; `offered` is injectable for exactly that reason,
/// and these tests drive BOTH arms.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show kReleaseMode;
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

  /// The toggle inside a fixed-height column, so "renders nothing" can be
  /// measured as height, not just as a missing finder.
  Future<double> pumpAndMeasure( WidgetTester tester, ServerContextService service, { required bool offered } ) async {
    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [ ServerContextToggle( service: service, offered: offered ) ],
        ),
      ),
    ) );
    return tester.getSize( find.byType( ServerContextToggle ) ).height;
  }

  testWidgets( "a release build gets no switch and no space where it was", ( tester ) async {
    final svc    = await loadService( tester );
    final height = await pumpAndMeasure( tester, svc, offered: false );

    expect( find.byKey( const Key( TestKeys.serverContextToggle ) ), findsNothing );
    expect( find.text( "Active server" ), findsNothing );
    expect( height, 0, reason: "the 32px lead-in belongs to the widget, so release leaves no gap" );
  } );

  testWidgets( "a debug or profile build gets the full switch", ( tester ) async {
    final svc    = await loadService( tester );
    final height = await pumpAndMeasure( tester, svc, offered: true );

    expect( find.byKey( const Key( TestKeys.serverContextToggle ) ), findsOneWidget );
    expect( find.text( "Active server" ), findsOneWidget );
    expect( height, greaterThan( 32 ) );
  } );

  testWidgets( "a debug build — which is what the phone gets — is offered the switch by default", ( tester ) async {
    final svc = await loadService( tester );

    expect( kReleaseMode, isFalse, reason: "flutter test, and `flutter build apk --debug`, both run here" );
    expect(
      ServerContextToggle( service: svc ).offered,
      isTrue,
      reason: "gating on kReleaseMode itself, or on a bare false, would take the switch "
              "away from the real-phone session",
    );
  } );

  test( "the default is the build mode, not a hard-coded true", () {
    // kReleaseMode is a compile-time constant, so in a debug test run a
    // hard-coded `true` reads identically to `!kReleaseMode`. Source is the
    // only place that difference is visible. The exact parameter spelling is
    // matched, which the doc comment above it does not contain.
    final source = File( "lib/features/settings/presentation/server_context_toggle.dart" ).readAsStringSync();
    expect( source, contains( "this.offered = !kReleaseMode," ) );
  } );
}
