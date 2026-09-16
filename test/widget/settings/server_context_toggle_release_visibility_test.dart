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
///
/// Those source assertions read the code with its comments stripped. A test
/// that forbids a string everywhere in a file, comments and all, forbids
/// writing down the hazard it exists to guard — and the first person who
/// hits that deletes the test, not the comment.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/presentation/server_context_toggle.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';

/// Build-mode constants a gate could be written against. `dart.vm.product` is
/// on the list because `const bool.fromEnvironment( "dart.vm.product" )` is
/// release mode under another name, reads false under `flutter test` like the
/// rest of them, and is already an idiom in this repo
/// (lib/core/monitoring/performance_monitor.dart:663).
///
/// `bool.fromEnvironment` in general is NOT forbidden: a `--dart-define` the
/// build sets deliberately is one of the escape hatches the widget's docstring
/// offers to anyone who wants the picker hidden from strangers. It is the
/// build MODE that must not decide this, not compile-time configuration.
const buildModeGates = [
  "kReleaseMode",
  "kProfileMode",
  "kDebugMode",
  "dart.vm.product",
];

/// A file's code with every comment removed, so prose may name the constants
/// the assertions forbid. Strips `//` to end of line, `/* ... */` blocks, and
/// tracks quotes so a `//` inside a string literal — a URL, say — survives.
String codeOnly( String path ) {
  final source = File( path ).readAsStringSync();
  final code   = StringBuffer();
  String? quote;
  var inBlock = false;

  for ( var i = 0; i < source.length; i++ ) {
    final char = source[ i ];
    final next = i + 1 < source.length ? source[ i + 1 ] : "";

    if ( inBlock ) {
      if ( char == "*" && next == "/" ) {
        inBlock = false;
        i      += 1;
      }
      continue;
    }
    if ( quote == null && char == "/" && next == "/" ) {
      while ( i < source.length && source[ i ] != "\n" ) {
        i += 1;
      }
      code.write( "\n" );
      continue;
    }
    if ( quote == null && char == "/" && next == "*" ) {
      inBlock = true;
      i      += 1;
      continue;
    }
    if ( quote != null && char == r"\" ) {
      code.write( char );
      i += 1;
      if ( i < source.length ) code.write( source[ i ] );
      continue;
    }
    if ( char == quote ) {
      quote = null;
    } else if ( quote == null && ( char == "'" || char == '"' ) ) {
      quote = char;
    }
    code.write( char );
  }
  return code.toString();
}

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

  // That every shipped context is reachable as a segment on the real login
  // screen is already pinned by test/widget/auth/login_screen_test.dart:166-178,
  // which pumps LoginScreen and asserts the toggle plus all four segments.

  test( "the widget carries no build-mode gate on its visibility", () {
    // The mutant this catches: reintroducing `offered = !kReleaseMode` and an
    // early `SizedBox.shrink()`. Every widget test above still passes under
    // that mutant, because `flutter test` runs in debug — only the source
    // tells the two apart.
    final code = codeOnly( togglePath );
    for ( final gate in buildModeGates ) {
      expect(
        code,
        isNot( contains( gate ) ),
        reason: "a release build is exactly the build that needs the picker most, so $gate must not decide this",
      );
    }
  } );

  test( "the login screen's mount carries no build-mode gate either", () {
    // The login screen is the toggle's ONLY mount and the only pre-auth
    // surface, so a build-mode gate at the call site strands a phone just as
    // thoroughly as one inside the widget.
    //
    // That the mount is reached at RUNTIME is login_screen_test.dart's job,
    // not this one's: a gate on some other compile-time flag leaves this
    // source assertion green and reddens that file instead, which is where a
    // pumped LoginScreen can see the toggle go missing.
    final code = codeOnly( loginPath );
    expect( code, contains( "ServerContextToggle(" ) );
    for ( final gate in buildModeGates ) {
      expect(
        code,
        isNot( contains( gate ) ),
        reason: "Settings sits behind AuthGate, so there is no second place to put this — $gate cannot gate the mount",
      );
    }
  } );
}
