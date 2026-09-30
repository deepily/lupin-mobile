import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:lupin_mobile/core/app_initialization.dart';
import 'package:lupin_mobile/app.dart';
import 'package:flutter/material.dart';

/// Minimal integration_test smoke to prove scaffolding works.
///
/// Confirms:
///   - IntegrationTestWidgetsFlutterBinding bootstraps cleanly.
///   - AppInitialization completes (DI + storage + logging).
///   - LupinMobileApp pumps a first frame without throwing.
///
/// Intentionally does NOT reach into specific screens (login/inbox/etc.);
/// those come later as the `integration_test/` suite grows. This is the
/// hello-world baseline.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets( "app boots without error", ( tester ) async {
    await AppInitialization.initialize(
      enableDebugLogging  : true,
      enableFileLogging   : false,
      enableRemoteLogging : false,
    );
    await tester.pumpWidget( const LupinMobileApp() );
    await tester.pump( const Duration( seconds: 1 ) );
    // If we got here without exception, scaffolding is green.
    expect( find.byType( MaterialApp ), findsWidgets );
  } );
}
