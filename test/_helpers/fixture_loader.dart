import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Resolves a fixture path relative to `test/fixtures/`.
///
/// Tests run with CWD = package root, so File I/O under `test/` works.
String _fixturePath( String relativePath ) => "test/fixtures/$relativePath";

/// Load a JSON fixture as a decoded Map. Throws FileSystemException if the
/// fixture is missing — a loud failure is the whole point of this pattern.
Map<String, dynamic> loadFixture( String relativePath ) {
  final file = File( _fixturePath( relativePath ) );
  final text = file.readAsStringSync();
  return jsonDecode( text ) as Map<String, dynamic>;
}

/// Wrap a fixture as a Dio `ResponseBody`, for use in stubbed
/// `HttpClientAdapter`s (see `test/unit/_helpers/stub_dio.dart` and
/// `test/unit/auth/auth_repository_test.dart`).
///
/// Usage:
///   adapter.handlers["POST /auth/login"] =
///     ( _ ) => jsonBodyFromFixture( "auth/login_response.json" );
ResponseBody jsonBodyFromFixture(
  String relativePath, {
  int status = 200,
} ) {
  final body = File( _fixturePath( relativePath ) ).readAsStringSync();
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [ Headers.jsonContentType ],
    },
  );
}
