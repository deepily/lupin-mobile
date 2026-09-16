/// The server switch renders in EVERY build mode, release included.
///
/// ca07b57 hid it in release, and that stranded the builds people actually
/// install: the login screen is the toggle's only mount, Settings is behind
/// AuthGate, and the shipped default context is the emulator-only 10.0.2.2.
/// A release APK with no picker therefore boots unreachable with no way out.
/// These tests pin the switch as always-on, which is Rick's ruling.
///
/// `kReleaseMode` is a compile-time constant, so a debug test run can never
/// observe the release arm of a gate written against it — a reintroduced
/// `!kReleaseMode` would render identically here. Source is the only place
/// that difference is visible, hence the source assertions below: they are
/// what actually fails if the gate comes back.
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
  const togglePath = "lib/features/settings/presentation/server_context_toggle.dart";
  const loginPath  = "lib/features/auth/presentation/login_screen.dart";

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

  /// The toggle inside a fixed-height column, so "renders something" can be
  /// measured as height, not just as a present finder.
  Future<double> pumpAndMeasure( WidgetTester tester, ServerContextService service ) async {
    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [ ServerContextToggle( service: service ) ],
        ),
      ),
    ) );
    return tester.getSize( find.byType( ServerContextToggle ) ).height;
  }

  testWidgets( "the switch renders with no flag standing between it and the screen", ( tester ) async {
    final svc    = await loadService( tester );
    final height = await pumpAndMeasure( tester, svc );

    expect( find.byKey( const Key( TestKeys.serverContextToggle ) ), findsOneWidget );
    expect( find.text( "Active server" ), findsOneWidget );
    expect( height, greaterThan( 32 ), reason: "the widget's own 32px lead-in plus the tile and segments" );
  } );

  testWidgets( "every shipped context is reachable as a segment, so a phone can leave 10.0.2.2", ( tester ) async {
    final svc = await loadService( tester );
    await pumpAndMeasure( tester, svc );

    for ( final c in svc.all ) {
      expect(
        find.byKey( Key( "${TestKeys.serverContextSegmentPrefix}${c.id}" ) ),
        findsOneWidget,
        reason: "${c.id} has to be pickable pre-auth, including in a release build",
      );
    }
  } );

  test( "the widget carries no build-mode gate on its visibility", () {
    // The mutant this catches: reintroducing `offered = !kReleaseMode` and an
    // early `SizedBox.shrink()`. Every widget test above still passes under
    // that mutant, because `flutter test` runs in debug — only the source
    // tells the two apart.
    final source = File( togglePath ).readAsStringSync();
    expect(
      source,
      isNot( contains( "kReleaseMode" ) ),
      reason: "a release build is exactly the build that needs the picker most",
    );
    expect( source, isNot( contains( "kProfileMode" ) ) );
    expect( source, isNot( contains( "kDebugMode" ) ) );
  } );

  test( "the login screen mounts the switch unconditionally", () {
    // The login screen is the toggle's ONLY mount and the only pre-auth
    // surface, so a build-mode gate at the call site strands a phone just as
    // thoroughly as one inside the widget.
    final source = File( loginPath ).readAsStringSync();
    expect( source, contains( "ServerContextToggle(" ) );
    expect(
      source,
      isNot( contains( "kReleaseMode" ) ),
      reason: "Settings sits behind AuthGate, so there is no second place to put this",
    );
  } );
}
