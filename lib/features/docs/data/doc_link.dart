/// Parses doc-viewer links out of a notification abstract and classifies them.
///
/// It imports neither Flutter nor IO, so the classification runs without a widget harness.
/// An abstract carries markdown links whose href is a route of the Lupin web app, such as
/// `[Open: <filename>](/app/docs?path=<project>/<rel>)`.
/// The mobile client does not load that route. It maps the href onto the backend's
/// raw-content endpoint and renders the bytes natively.

library;

/// What a parsed href turned out to be.
///
/// An `unknown` link is a normal outcome, not an error: an abstract is prose, and prose
/// contains links the app has no business following. It renders as inert text.
enum DocLinkKind {
  /// A project documentation file, served by `GET /api/docs/file`.
  docs,

  /// An `io/` artifact (generated report, podcast script), served by
  /// `GET /api/io/file`.
  io,

  /// An absolute `http(s)` URL belonging to someone else.
  ///
  /// It is handed to the system browser behind a confirm, never opened in-app.
  external,

  /// Anything the app declines to follow, including the retired `?scope=` form.
  unknown,
}

/// One link found in an abstract, classified and resolved to the request that fetches it.
class DocLink {
  /// Classification, which decides whether the link is tappable and what a tap does.
  final DocLinkKind kind;

  /// The href exactly as written in the abstract, never rewritten.
  ///
  /// The UI shows it so the user sees what is about to open, and an `unknown` link is
  /// reported by it.
  final String rawHref;

  /// The markdown link's display text.
  final String label;

  /// Registered project name, the first path segment.
  ///
  /// It is null unless [kind] is [DocLinkKind.docs].
  final String? project;

  /// Path within the project, with no leading slash.
  ///
  /// It is null unless [kind] is [DocLinkKind.docs] or [DocLinkKind.io].
  final String? relPath;

  /// Backend path to request, empty for [DocLinkKind.external] and [DocLinkKind.unknown].
  final String apiPath;

  /// Query parameters for [apiPath], already percent-decoded.
  ///
  /// Dio encodes on the way out, so encoding here would encode twice.
  final Map<String, String> query;

  /// Creates a classified link.
  const DocLink( {
    required this.kind,
    required this.rawHref,
    required this.label,
    required this.apiPath,
    required this.query,
    this.project,
    this.relPath,
  } );

  /// True when tapping this link should do something in-app.
  bool get isFetchable => kind == DocLinkKind.docs || kind == DocLinkKind.io;

  /// True when this link is a tap target at all.
  ///
  /// Fetchable links qualify, and so do external URLs, which open in the system browser.
  bool get isTappable => isFetchable || kind == DocLinkKind.external;

  /// Filename of the target, for titles and share filenames.
  ///
  /// It falls back to the link label when there is no path to take a basename from.
  String get displayName {
    if ( relPath == null || relPath!.isEmpty ) return label;
    final segments = relPath!.split( "/" ).where( ( s ) => s.isNotEmpty );
    return segments.isEmpty ? label : segments.last;
  }

  @override
  String toString() => "DocLink($kind, $rawHref)";
}

/// Matches a markdown inline link: `[label](href)`.
///
/// The label group rejects nested brackets so that two links on one line do not merge.
/// The href group stops at the first `)`, which fits the hrefs emitted (no parentheses in paths).
final RegExp _markdownLink = RegExp( r'\[([^\]]*)\]\(([^)\s]+)\)' );

/// Every link in [abstractText], in the order they appear.
///
/// Requires:
///     - abstractText may be null or empty
///
/// Ensures:
///     - returns an empty list for null, empty, or link-free input
///     - returns one DocLink per markdown link, including `unknown` ones, so
///       callers can tell "no links" from "links the app will not follow"
///     - never throws on malformed input; anything unparseable classifies as
///       DocLinkKind.unknown
List<DocLink> parseDocLinks( String? abstractText ) {
  if ( abstractText == null || abstractText.isEmpty ) return const [];

  final links = <DocLink>[];
  for ( final match in _markdownLink.allMatches( abstractText ) ) {
    final label = match.group( 1 ) ?? "";
    final href  = match.group( 2 ) ?? "";
    if ( href.isEmpty ) continue;
    links.add( classifyDocHref( href, label: label ) );
  }
  return links;
}

/// True when [abstractText] carries at least one link the app would fetch.
///
/// The card's document-icon badge promises something to open, so an abstract whose only
/// links are external or unrecognized must not show it.
bool hasFetchableDocLink( String? abstractText ) =>
    parseDocLinks( abstractText ).any( ( l ) => l.isFetchable );

/// Classify one href and resolve it to a backend request.
///
/// Requires:
///     - href is a non-empty string
///
/// Ensures:
///     - `/app/docs?path=<project>/<rel>` → DocLinkKind.docs targeting
///       `/api/docs/file`, with project and relPath split out
///     - `/api/docs/file?path=...` → DocLinkKind.docs, passed through
///     - `/api/io/file?path=...` → DocLinkKind.io, passed through
///     - `http://` or `https://` → DocLinkKind.external
///     - a doc href carrying the retired `scope` parameter → DocLinkKind.unknown
///     - anything else → DocLinkKind.unknown
///     - never throws; an unparseable href classifies as unknown
DocLink classifyDocHref( String href, { String label = "" } ) {
  DocLink unknown() => DocLink(
    kind    : DocLinkKind.unknown,
    rawHref : href,
    label   : label,
    apiPath : "",
    query   : const {},
  );

  Uri uri;
  try {
    uri = Uri.parse( href );
  } catch ( _ ) {
    return unknown();
  }

  if ( uri.scheme == "http" || uri.scheme == "https" ) {
    return DocLink(
      kind    : DocLinkKind.external,
      rawHref : href,
      label   : label,
      apiPath : "",
      query   : const {},
    );
  }

  // Only same-origin absolute paths are ours. A relative href has no project context,
  // so it cannot be resolved and is not guessed at.
  if ( !href.startsWith( "/" ) ) return unknown();

  // `queryParameters` percent-decodes for us, so `path` arrives usable.
  final path = uri.queryParameters[ "path" ];

  // The retired `?scope=` form is not rewritten. The backend answers 400 on it, so a tap
  // would offer a failure. It is detected explicitly so the rule stays easy to find.
  // Design: src/docs/decisions/README.md (R-DOC-retired-scope)
  if ( uri.queryParameters.containsKey( "scope" ) ) return unknown();

  switch ( uri.path ) {
    // SPA route → raw-content endpoint. `path` is `<project>/<rel>`.
    case "/app/docs":
    case "/api/docs/file":
      if ( path == null || path.isEmpty ) return unknown();
      final split = _splitProjectPath( path );
      if ( split == null ) return unknown();
      return DocLink(
        kind    : DocLinkKind.docs,
        rawHref : href,
        label   : label,
        project : split.project,
        relPath : split.relPath,
        apiPath : "/api/docs/file",
        query   : { "path": path },
      );

    // io/ artifacts. `path` is relative to io/, with no project segment.
    case "/api/io/file":
      if ( path == null || path.isEmpty ) return unknown();
      return DocLink(
        kind    : DocLinkKind.io,
        rawHref : href,
        label   : label,
        relPath : path,
        apiPath : "/api/io/file",
        query   : { "path": path },
      );

    default:
      return unknown();
  }
}

/// The `<project>/<rel>` split of a docs `path` parameter.
class _ProjectPath {
  final String project;
  final String relPath;
  const _ProjectPath( this.project, this.relPath );
}

/// Split `<project>/<rel>` into its two halves.
///
/// Returns null when there is no project segment or no remainder.
///
/// A bare `path=README.md` names no project and the backend cannot resolve it, so the
/// split declines rather than inventing one.
_ProjectPath? _splitProjectPath( String path ) {
  final trimmed = path.startsWith( "/" ) ? path.substring( 1 ) : path;
  final slash   = trimmed.indexOf( "/" );
  if ( slash <= 0 || slash == trimmed.length - 1 ) return null;
  return _ProjectPath( trimmed.substring( 0, slash ), trimmed.substring( slash + 1 ) );
}

/// The scope name the io root answers to in listings.
const ioScope = "io";

/// The link that fetches [relPath] inside [scope], for browsing.
///
/// The browser builds its own links from each entry's scope-relative path and does not
/// follow its `view_url`. In `io` an mp3's `view_url` is the web audio page and a pdf's
/// has no project segment, so following it would fetch the wrong thing.
///
/// Requires:
///   - [scope] is a registered doc scope, or [ioScope]
///   - [relPath] is relative to that scope; empty means the scope's root
///
/// Ensures:
///   - io → `/api/io/file?path=<rel>`, with `.` standing for the io root,
///     because that endpoint requires a non-empty path
///   - any other scope → `/api/docs/file?path=<scope>/<rel>`, or `<scope>`
///     alone at its root
DocLink docLinkFor( String scope, String relPath, { String label = "" } ) {
  final rel = relPath.startsWith( "/" ) ? relPath.substring( 1 ) : relPath;
  if ( scope == ioScope ) {
    final path = rel.isEmpty ? "." : rel;
    return DocLink(
      kind    : DocLinkKind.io,
      rawHref : "/api/io/file?path=${Uri.encodeQueryComponent( path )}",
      label   : label,
      relPath : rel,
      apiPath : "/api/io/file",
      query   : { "path": path },
    );
  }
  final path = rel.isEmpty ? scope : "$scope/$rel";
  return DocLink(
    kind    : DocLinkKind.docs,
    rawHref : "/app/docs?path=${Uri.encodeQueryComponent( path )}",
    label   : label,
    project : scope,
    relPath : rel,
    apiPath : "/api/docs/file",
    query   : { "path": path },
  );
}

/// The parent directory of [rel], empty at the top level.
String _dirname( String rel ) {
  final i = rel.lastIndexOf( "/" );
  return i <= 0 ? "" : rel.substring( 0, i );
}

/// The folder holding the file [link] points at, for the Folder button.
///
/// Ensures:
///   - null for a link that is not a docs or io link
///   - a file at a scope's top level → that scope's root
DocLink? folderLinkFor( DocLink link ) {
  final rel = link.relPath;
  if ( rel == null ) return null;
  switch ( link.kind ) {
    case DocLinkKind.docs:
      return docLinkFor( link.project!, _dirname( rel ), label: "Folder" );
    case DocLinkKind.io:
      return docLinkFor( ioScope, _dirname( rel ), label: "Folder" );
    case DocLinkKind.external:
    case DocLinkKind.unknown:
      return null;
  }
}
