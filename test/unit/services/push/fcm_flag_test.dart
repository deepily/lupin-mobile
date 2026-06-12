/// AC-S5.4 — the ENABLE_FCM compile-time flag defaults OFF, so Stage-1
/// builds (and this very test run, which compiles `fcm_bootstrap.dart`
/// WITHOUT google-services.json present) carry no Firebase dependency at
/// runtime. The flag is grep-able as `--dart-define=ENABLE_FCM` (pinned in
/// the bootstrap's docstring and build command).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';

void main() {
  group( 'ENABLE_FCM flag (S5, AC-S5.4)', () {
    test( 'defaults OFF — Stage-1 regression safety', () {
      expect( kEnableFcm, isFalse,
          reason: 'plain test/build runs must never touch Firebase; '
              'enable explicitly with --dart-define=ENABLE_FCM=true' );
    } );

    test( 'initFcmIfEnabled is a no-op (returns null) when the flag is OFF', () async {
      // Would throw immediately if it reached Firebase.initializeApp()
      // (no google-services.json, no platform channel in the VM).
      final service = await initFcmIfEnabled();
      expect( service, isNull );
    } );

    test( 'auth hooks are safe no-ops when FCM is disabled', () async {
      await fcmOnAuthenticated( 'rick@test.com' );   // must not throw
      await fcmOnLoggedOut();                        // must not throw
    } );
  } );
}
