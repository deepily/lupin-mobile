/// Typed results of fetching a doc-viewer target.
///
/// `GET /api/docs/file` answers with raw text, raw image bytes, or a JSON directory
/// listing, depending on what the path resolves to.
/// The client models that choice explicitly and does not guess from the file extension.

library;

/// How a fetched document should be rendered.
enum DocContentKind {
  /// `text/markdown` — render with the Markdown widget.
  markdown,

  /// Any other `text/*` (source code, JSON, YAML, plain text), rendered as monospaced source.
  ///
  /// It is never fed to the markdown renderer, which would turn `#` comments into headings.
  source,

  /// `text/html`, currently rendered as source like the other text kinds.
  ///
  /// It stays its own kind so a dedicated renderer can be added later.
  html,

  /// `image/*` — render the bytes directly.
  image,

  /// A directory, not a file. Carries a listing instead of content.
  directory,

  /// A file the viewer cannot preview: PDF, audio, video, office documents.
  ///
  /// It is rendered as a "no preview, use Download" notice and never decoded as text,
  /// which would paint the bytes as garbage.
  binary,
}

/// One fetched document.
class DocContent {
  /// What to render this as.
  final DocContentKind kind;

  /// Media type exactly as the server reported it, such as `text/markdown; charset=utf-8`.
  ///
  /// It is kept verbatim for display and debugging.
  final String mediaType;

  /// Decoded text, null for [DocContentKind.image] and [DocContentKind.directory].
  final String? text;

  /// Raw bytes exactly as the server sent them, set for every fetched file.
  ///
  /// Download saves these bytes and never the rendered view, so for markdown it saves the
  /// source. It is null for content handed in by the caller and for directory listings.
  final List<int>? bytes;

  /// Directory entries, set only for [DocContentKind.directory].
  final DocDirectoryListing? listing;

  /// Creates a fetched document.
  const DocContent( {
    required this.kind,
    required this.mediaType,
    this.text,
    this.bytes,
    this.listing,
  } );
}

/// One entry in a directory listing.
class DocDirectoryEntry {
  /// The entry's file or folder name.
  final String name;

  /// The entry's path relative to its scope.
  final String path;

  /// True for a folder, false for a file.
  final bool   isDirectory;

  /// File size in bytes, or null when the server gave none.
  final int?   sizeBytes;

  /// Creates a directory entry.
  const DocDirectoryEntry( {
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
  } );

  /// Reads an entry from the server's JSON, which uses `kind` and `rel_path`.
  ///
  /// The older `type` and `path` keys are still read as fallbacks.
  factory DocDirectoryEntry.fromJson( Map<String, dynamic> json ) {
    final kind = ( json[ "kind" ] ?? json[ "type" ] )?.toString();
    return DocDirectoryEntry(
      name        : ( json[ "name" ] ?? "" ).toString(),
      path        : ( json[ "rel_path" ] ?? json[ "path" ] ?? "" ).toString(),
      isDirectory : kind == "directory" || json[ "is_directory" ] == true,
      sizeBytes   : ( json[ "size" ] as num? )?.toInt(),
    );
  }
}

/// A directory's contents, plus the parent to navigate up to.
class DocDirectoryListing {
  /// The directory's path relative to its scope.
  final String  path;

  /// The registered doc scope the directory belongs to.
  final String  scope;

  /// The parent to navigate up to, null at the scope root or outside the whitelist.
  final String? parent;

  /// The directory's entries.
  final List<DocDirectoryEntry> entries;

  /// Creates a directory listing.
  const DocDirectoryListing( {
    required this.path,
    required this.scope,
    required this.entries,
    this.parent,
  } );

  /// Reads a listing from the server's JSON, treating a missing entry list as empty.
  factory DocDirectoryListing.fromJson( Map<String, dynamic> json ) {
    final raw = json[ "entries" ];
    return DocDirectoryListing(
      path    : ( json[ "path" ] ?? "" ).toString(),
      scope   : ( json[ "scope" ] ?? "" ).toString(),
      parent  : json[ "parent" ]?.toString(),
      entries : raw is List
          ? raw
              .whereType<Map>()
              .map( ( e ) => DocDirectoryEntry.fromJson( Map<String, dynamic>.from( e ) ) )
              .toList()
          : const [],
    );
  }
}

/// One browsable root: a registered doc scope and the folders it exposes.
///
/// The list comes from `GET /api/docs/scopes`. The built-in `io` root is not in it, so
/// the Roots panel adds that one itself.
class DocScope {
  /// The registered scope name.
  final String       name;

  /// The folders the scope exposes.
  final List<String> allowedPrefixes;

  /// Creates a scope.
  const DocScope( { required this.name, required this.allowedPrefixes } );

  /// Reads a scope from the server's JSON, treating missing prefixes as none.
  factory DocScope.fromJson( Map<String, dynamic> json ) {
    final raw = json[ "allowed_prefixes" ];
    return DocScope(
      name            : ( json[ "name" ] ?? "" ).toString(),
      allowedPrefixes : raw is List ? raw.map( ( e ) => e.toString() ).toList() : const [],
    );
  }
}

/// A doc fetch that failed.
///
/// The [message] is the server's own `detail` string, unedited, wherever the server gave one.
///
/// The endpoint's refusals are written for a person and draw distinctions a paraphrase
/// would lose. "Credential material" is a fact about the file; "could not be read or
/// decoded" is a fact about the disk or mount.
class DocApiException implements Exception {
  /// The failure text to show the user.
  final String message;

  /// The HTTP status code, or null when the failure had none.
  final int?   statusCode;

  /// Creates a fetch failure.
  const DocApiException( this.message, { this.statusCode } );

  @override
  String toString() => "DocApiException($statusCode): $message";
}
