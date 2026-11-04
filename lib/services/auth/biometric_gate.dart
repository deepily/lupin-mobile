import 'package:local_auth/local_auth.dart';

/// Result of a biometric prompt.
enum BiometricOutcome {
  /// The user passed the biometric check.
  authenticated,

  /// The user dismissed the prompt or failed the check.
  cancelled,

  /// No biometric is enrolled or the hardware is missing.
  unavailable,

  /// The check threw an error.
  failed
}

/// Wraps `local_auth` behind a simple API.
///
/// When no biometric is enrolled or the hardware is missing, it returns `unavailable`, so callers can
/// fall back to password login without surfacing an error.
class BiometricGate {
  final LocalAuthentication _auth;

  /// Creates a gate on [auth], or on a new `LocalAuthentication` by default.
  BiometricGate( [ LocalAuthentication? auth ] )
      : _auth = auth ?? LocalAuthentication();

  /// True when the device supports biometrics and can check them; false on any error.
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

  /// Prompts for a biometric with [reason] and reports the outcome.
  ///
  /// Returns `unavailable` when none is enrolled, `cancelled` when the user declines and `failed` on any error.
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
