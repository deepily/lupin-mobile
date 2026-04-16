import 'package:local_auth/local_auth.dart';

enum BiometricOutcome { authenticated, cancelled, unavailable, failed }

/// Wraps `local_auth` with a simple boolean-style API. When no biometric
/// is enrolled or hardware is missing, returns `unavailable` so callers
/// can fall back to password login without surfacing an error.
class BiometricGate {
  final LocalAuthentication _auth;

  BiometricGate( [ LocalAuthentication? auth ] )
      : _auth = auth ?? LocalAuthentication();

  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if ( !supported ) return false;
      final canCheck  = await _auth.canCheckBiometrics;
      return canCheck;
    } catch ( _ ) {
      return false;
    }
  }

  Future<BiometricOutcome> authenticate( {
    String reason = "Unlock Lupin",
  } ) async {
    try {
      final enrolled = await _auth.getAvailableBiometrics();
      if ( enrolled.isEmpty ) return BiometricOutcome.unavailable;

      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly : true,
          stickyAuth    : true,
        ),
      );
      return ok ? BiometricOutcome.authenticated : BiometricOutcome.cancelled;
    } catch ( _ ) {
      return BiometricOutcome.failed;
    }
  }
}
