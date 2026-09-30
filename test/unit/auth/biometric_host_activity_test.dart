// Row 8ff78c69 — fingerprint unlock needs a FragmentActivity host.
//
// `local_auth` on Android shows its prompt through a FragmentActivity. With a
// plain `FlutterActivity`, `authenticate()` throws, `BiometricGate` maps the
// throw to `BiometricOutcome.failed`, and AuthBloc falls through to the password
// screen with no error shown. Found on Rick's phone 2026-09-28: tapping a wake
// notification opened the password screen, and the server log showed no refresh
// attempt at all. No Dart test can reach the native host, so this pins the source.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test( 'MainActivity extends FlutterFragmentActivity so the fingerprint prompt can show', () {
    final src = File(
      'android/app/src/main/kotlin/ai/deepily/lupin_mobile/MainActivity.kt',
    ).readAsStringSync();

    expect( src, contains( 'import io.flutter.embedding.android.FlutterFragmentActivity' ) );
    expect( src, matches( RegExp( r'class\s+MainActivity\s*:\s*FlutterFragmentActivity\s*\(\s*\)' ) ) );
  } );
}
