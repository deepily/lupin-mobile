/// Pure parsing of doc-viewer links out of a notification `abstract`.
///
/// Deliberately free of Flutter and IO imports so the whole classification
/// surface is unit-testable without a widget harness.
///
/// The fleet convention (global CLAUDE.md, "DOCUMENT VIEWER LINKS") is that an
/// abstract carries markdown links whose href is a Lupin SPA route:
///
///     [Open: <filename>](/app/docs?path=<project>/<rel>)
///
/// The mobile client does not load that SPA route. It maps the href onto the
/// backend's raw-content endpoint and renders the bytes natively, which is why
/// this file's job is classify-and-normalize rather than navigate.

library;

/// What a parsed href turned out to be.
///
/// `unknown` is a first-class outcome, not an error: an abstract is prose, and
/// prose contains links we have no business following. An `unknown` link
/// renders as inert text.
enum DocLinkKind {
  /// A project documentation file, served by `GET /api/docs/file`.
  docs,

  /// An `io/` artifact (generated report, podcast script), served by
  /// `GET /api/io/file`.
  io,

  /// An absolute `http(s)` URL belonging to someone else. Handed to the system
  /// browser behind a confirm, never opened in-app.
  external,

  /// Anything we decline to follow — including the RETIRED `?scope=` form.
  unknown,
}

/// One link found in an abstract, classified and (for our own kinds) resolved
/// to the API request that will fetch its bytes.
class DocLink {
  /// Classification. Drives both whether the link is tappable and what happens
  /// on tap.
  final DocLinkKind kind;

  /// The href exactly as written in the abstract, never rewritten. Kept so the
  /// UI can show the user what it is about to open, and so an `unknown` link
  /// can be reported precisely.
  final String rawHref;

  /// The markdown link's display text.
  final String label;

  /// Registered project/scope name — the first path segment. Null unless
  /// [kind] is [DocLinkKind.docs].
  final String? project;

  /// Path within the project, no leading slash. Null unless [kind] is
  /// [DocLinkKind.docs] or [DocLinkKind.io].
  final String? relPath;

  /// Backend path to request. Empty for [DocLinkKind.external] and
  /// [DocLinkKind.unknown].
  final String apiPath;

  /// Query parameters for [apiPath], already percent-DECODED. Dio encodes on
  /// the way out, so pre-encoding here would double-encode.
  final Map<String, String> query;

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

  /// True when this link should be offered as a tap target at all — fetchable
  /// links plus external URLs, which open in the system browser.
  bool get isTappable => isFetchable || kind == DocLinkKind.external;

  /// Filename of the target, for titles and share filenames. Falls back to the
  /// link label when there is no path to take a basename from.
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
/// The label group is non-greedy and rejects nested brackets so that two links
/// on one line do not merge into a single match. The href group stops at the
/// first `)`, which is correct for the hrefs we emit (no parenthesized paths).
final RegExp _markdownLink = RegExp( r'\[([^\]]*)\]\(([^)\s]+)\)' );

/// Every link in [abstractText], in the order they appear.
///
/// Requires:
///     - abstractText may be null or empty
///
/// Ensures:
///     - returns an empty list for null, empty, or link-free input
///     - returns one DocLink per markdown link, including `unknown` ones, so
///       callers can distinguish "no links" from "links we won't follow"
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

/// True when [abstractText] carries at least one link we would actually fetch.
///
/// This is the predicate behind the card's document-icon badge: the badge
/// promises "there is something here to open", so an abstract whose only links
/// are external or unrecognized must NOT show it.
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
///     - a doc href carrying the RETIRED `scope` parameter → DocLinkKind.unknown
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

  // Only same-origin absolute paths are ours. A relative href ("./notes.md")
  // has no project context, so we cannot resolve it and will not guess.
  if ( !href.startsWith( "/" ) ) return unknown();

  // `queryParameters` percent-decodes for us, so `path` arrives usable.
  final path = uri.queryParameters[ "path" ];

  // RETIRED `?scope=` form. Rick 2026-09-08: modern format only — we do not
  // rewrite legacy links. The backend answers 400 on this parameter (aggressive
  // -400 policy, 2026-05-21), so offering a tap here would offer a failure.
  // Detected EXPLICITLY rather than by falling through, so this stays a
  // decision someone can find and reverse.
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
/// Returns null when there is no project segment or no remainder — a bare
/// `path=README.md` names no project and the backend cannot resolve it, so we
/// decline rather than inventing one.
_ProjectPath? _splitProjectPath( String path ) {
  final trimmed = path.startsWith( "/" ) ? path.substring( 1 ) : path;
  final slash   = trimmed.indexOf( "/" );
  if ( slash <= 0 || slash == trimmed.length - 1 ) return null;
  return _ProjectPath( trimmed.substring( 0, slash ), trimmed.substring( slash + 1 ) );
}
