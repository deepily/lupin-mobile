/// AC-S2.7 — the ONE place the microphone permission is REQUESTED.
///
/// 🔴 The plan's context table said "mic permission handled, with a
/// `requestMicPermission` test seam on `voice_reply_field.dart`". Both halves
/// were true separately and NEITHER was reusable. Verified at HEAD:
///
///   * `AsrService.startRecording()` only **checks** — `hasPermission()` then
///     throw. It never **requests**.
///   * The actual `Permission.microphone.request()` lived at TWO private sites
///     on TWO different recorder stacks: `_defaultMicPermission`, private to
///     `_VoiceReplyFieldState`, and `_requestPermissions` in
///     `voice_input_output_service.dart` (on `FlutterSoundRecorder`, not even
///     registered in the service locator).
///
/// Quick Ask would have been the THIRD copy. Consequence if left alone: a
/// first-run user holds the button and gets the inline error "Microphone
/// permission denied" **having never been asked** — the screen simply does not
/// work on a fresh install. That is not tidiness, it is whether the feature
/// functions.
library;

import 'package:permission_handler/permission_handler.dart';

/// The seam. Tests substitute this; production leaves it alone.
typedef MicPermissionRequester = Future<bool> Function();

/// Request the microphone permission, raising the system prompt when the
/// permission has not yet been decided.
///
/// Returns true iff recording is permitted afterwards. `request()` is a no-op
/// that returns the existing status when already granted or permanently
/// denied, so calling it on every capture is safe and is what makes the
/// first-run prompt appear at the moment the user reaches for the mic.
Future<bool> requestMicPermission() async {
  final status = await Permission.microphone.request();
  return status.isGranted;
}
