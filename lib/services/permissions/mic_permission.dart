/// The single place the microphone permission is requested.
///
/// `AsrService.startRecording` only checks the permission and throws when it is missing.
/// Without a request, a first-run user holds the button and gets "Microphone permission denied"
/// without being asked. The screen then does not work on a fresh install.
library;

import 'package:permission_handler/permission_handler.dart';

/// Test seam for [requestMicPermission]; production code uses the default.
typedef MicPermissionRequester = Future<bool> Function();

/// Requests the microphone permission and returns true when recording is permitted.
///
/// Raises the system prompt only while the permission is undecided. When it is already granted
/// or permanently denied, `request()` returns the existing status. Calling this on every capture
/// is therefore safe, and it shows the first-run prompt when the user reaches for the microphone.
Future<bool> requestMicPermission() async {
  final status = await Permission.microphone.request();
  return status.isGranted;
}
