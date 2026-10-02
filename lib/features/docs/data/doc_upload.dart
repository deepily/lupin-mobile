/// Uploads into a doc-viewer folder.
///
/// The request is `POST /api/docs/upload`, multipart: `dir` (`<project>/<rel-dir>` or
/// `io/<rel-dir>`), `file`, and `on_conflict` (refuse, replace or rename).
/// A 201 returns `{path, name, size, replaced, view_url}`, and a 409 carries
/// `detail.suggested_name`. A 400, 403, 404 or 413 carries a readable `detail`.
/// Expect a 403 on the external-repo mounts while they stay read-only.
library;

import 'dart:convert';

import 'doc_link.dart';

/// How the server should treat a name that is already taken.
enum DocUploadConflictMode {
  /// Reject the upload with a 409.
  refuse,

  /// Overwrite the existing file.
  replace,

  /// Store the upload under a free name the server picks.
  rename
}

/// One file the user picked, in memory.
class PickedDocFile {
  /// The file name the user picked.
  final String    name;

  /// The file contents.
  final List<int> bytes;

  /// Creates a picked file.
  const PickedDocFile( { required this.name, required this.bytes } );
}

/// Opens the platform's file chooser. Null when the user backed out.
typedef DocFilePicker = Future<PickedDocFile?> Function();

/// A stored upload.
class DocUploadResult {
  /// The stored file's path.
  final String path;

  /// The name the server actually used.
  final String name;

  /// The stored size in bytes.
  final int    size;

  /// True when the upload overwrote an existing file.
  final bool   replaced;

  /// Creates an upload result.
  const DocUploadResult( { required this.path, required this.name, required this.size, required this.replaced } );

  /// Reads a result from the server's JSON, defaulting missing fields to empty or zero.
  factory DocUploadResult.fromJson( Map<String, dynamic> json ) => DocUploadResult(
    path     : ( json[ "path" ] ?? "" ).toString(),
    name     : ( json[ "name" ] ?? "" ).toString(),
    size     : ( json[ "size" ] as num? )?.toInt() ?? 0,
    replaced : json[ "replaced" ] == true,
  );
}

/// The 409: the name is taken. The server names a free one.
class DocUploadConflict implements Exception {
  /// The server's explanation.
  final String  message;

  /// A free name the server suggests, or null when it gave none.
  final String? suggestedName;

  /// Creates a conflict.
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

/// True when [scope] is the io root, kept beside [uploadDirFor] so the two agree on its name.
bool isIoScope( String scope ) => scope == ioScope;

/// Whether a JWT says its holder is an admin.
///
/// This is a courtesy, as on the web: it decides whether Upload is offered. The server's
/// `require_admin` decides whether it works, so a wrong guess costs one 403 in a
/// snackbar and never a stored file.
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
