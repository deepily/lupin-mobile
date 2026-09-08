/// Typed results of fetching a doc-viewer target.
///
/// The backend endpoint is polymorphic — `GET /api/docs/file` answers with raw
/// text, raw image bytes, or a JSON directory listing depending on what the
/// path resolves to — so the client models that same polymorphism explicitly
/// rather than guessing from the file extension.

library;

/// How a fetched document should be rendered.
enum DocContentKind {
  /// `text/markdown` — render with the Markdown widget.
  markdown,

  /// Any other `text/*` (source code, JSON, YAML, plain text) — render as
  /// monospaced source. Deliberately NOT fed to the markdown renderer, which
  /// would mangle `#` comments into headings.
  source,

  /// `text/html`. Currently rendered as SOURCE alongside the other text kinds —
  /// kept as its own kind so the distinction survives for the day a real
  /// abstract links an .html file and earns a dedicated renderer.
  html,

  /// `image/*` — render the bytes directly.
  image,

  /// A directory, not a file. Carries a listing instead of content.
  directory,
}

/// One fetched document.
class DocContent {
  /// What to render this as.
  final DocContentKind kind;

  /// Media type exactly as the server reported it, e.g.
  /// `text/markdown; charset=utf-8`. Kept verbatim for display and debugging.
  final String mediaType;

  /// Decoded text. Null for [DocContentKind.image] and
  /// [DocContentKind.directory].
  final String? text;

  /// Raw bytes. Populated only for [DocContentKind.image].
  final List<int>? bytes;

  /// Directory entries. Populated only for [DocContentKind.directory].
  final DocDirectoryListing? listing;

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
  final String name;
  final String path;
  final bool   isDirectory;
  final int?   sizeBytes;

  const DocDirectoryEntry( {
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes,
  } );

  factory DocDirectoryEntry.fromJson( Map<String, dynamic> json ) {
    final type = json[ "type" ]?.toString();
    return DocDirectoryEntry(
      name        : ( json[ "name" ] ?? "" ).toString(),
      path        : ( json[ "path" ] ?? "" ).toString(),
      isDirectory : type == "directory" || json[ "is_directory" ] == true,
      sizeBytes   : ( json[ "size" ] as num? )?.toInt(),
    );
  }
}

/// A directory's contents, plus the parent to navigate up to (null at the
/// scope root, or when the parent falls outside the whitelist).
class DocDirectoryListing {
  final String  path;
  final String  scope;
  final String? parent;
  final List<DocDirectoryEntry> entries;

  const DocDirectoryListing( {
    required this.path,
    required this.scope,
    required this.entries,
    this.parent,
  } );

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

/// A doc fetch that failed.
///
/// [message] carries the server's own `detail` string UNEDITED wherever the
/// server supplied one. The doc endpoint's refusals are written to be read by a
/// human and draw distinctions we would lose by paraphrasing — notably
/// "this file's content is credential material" (a fact about the file) versus
/// "this file could not be read or decoded" (a fact about the disk or mount).
class DocApiException implements Exception {
  final String message;
  final int?   statusCode;

  const DocApiException( this.message, { this.statusCode } );

  @override
  String toString() => "DocApiException($statusCode): $message";
}
