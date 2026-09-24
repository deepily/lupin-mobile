/// ⬆ Upload into a doc-viewer folder (row 61ecfb22, parity with lupin 416d4b00).
///
/// The server contract, from `docs_files.py` at lupin `627ef22c8`:
/// `POST /api/docs/upload`, multipart `dir` (`<project>/<rel-dir>` or
/// `io/<rel-dir>`), `file`, `on_conflict` = refuse | replace | rename.
/// 201 → `{path, name, size, replaced, view_url}`; 409 → `detail.suggested_name`;
/// 400 / 403 / 404 / 413 carry a human `detail`.
///
/// ⚠️ A 403 IS EXPECTED on the external-repo mounts while they stay read-only
/// (Mr. Radio, 2026-09-24): only io and lupin take uploads today.
library;

import 'dart:convert';

import 'doc_link.dart';

/// How the server should treat a name that is already taken.
enum DocUploadConflictMode { refuse, replace, rename }

/// One file the user picked, in memory.
class PickedDocFile {
  final String    name;
  final List<int> bytes;

  const PickedDocFile( { required this.name, required this.bytes } );
}

/// Opens the platform's file chooser. Null when the user backed out.
typedef DocFilePicker = Future<PickedDocFile?> Function();

/// A stored upload.
class DocUploadResult {
  final String path;
  final String name;
  final int    size;
  final bool   replaced;

  const DocUploadResult( { required this.path, required this.name, required this.size, required this.replaced } );

  factory DocUploadResult.fromJson( Map<String, dynamic> json ) => DocUploadResult(
    path     : ( json[ "path" ] ?? "" ).toString(),
    name     : ( json[ "name" ] ?? "" ).toString(),
    size     : ( json[ "size" ] as num? )?.toInt() ?? 0,
    replaced : json[ "replaced" ] == true,
  );
}

/// The 409: the name is taken. The server names a free one.
class DocUploadConflict implements Exception {
  final String  message;
  final String? suggestedName;

  const DocUploadConflict( this.message, { this.suggestedName } );

  @override
  String toString() => "DocUploadConflict($message, $suggestedName)";
}

/// The `dir` form field for a listing's folder.
///
/// Ensures:
///   - io → `io` or `io/<path>`; any other scope → `<scope>` or `<scope>/<path>`
///   - never a trailing slash
String uploadDirFor( String scope, String path ) {
  final rel = path.replaceAll( RegExp( r'^/+|/+$' ), '' );
  return rel.isEmpty ? scope : "$scope/$rel";
}

/// True when [scope] is the io root — kept beside [uploadDirFor] so the two
/// agree on its name.
bool isIoScope( String scope ) => scope == ioScope;

/// Whether a JWT says its holder is an admin.
///
/// ⚠️ A COURTESY, AS ON THE WEB: it decides whether ⬆ Upload is OFFERED. The
/// server's `require_admin` decides whether it WORKS, and a wrong guess here
/// costs one 403 in a snackbar, never a stored file.
///
/// Ensures:
///   - true when the payload carries `roles` containing `admin`, or `role == "admin"`
///   - false for null, malformed or unsigned-looking tokens; never throws
bool tokenHasAdminRole( String? jwt ) {
  if ( jwt == null ) return false;
  final parts = jwt.split( "." );
  if ( parts.length < 2 ) return false;
  try {
    final payload = jsonDecode( utf8.decode( base64Url.decode( base64Url.normalize( parts[ 1 ] ) ) ) );
    if ( payload is! Map ) return false;
    final roles = payload[ "roles" ];
    if ( roles is List && roles.contains( "admin" ) ) return true;
    return payload[ "role" ] == "admin";
  } catch ( _ ) {
    return false;
  }
}
