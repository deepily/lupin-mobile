import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';

/// P1 of the abstract doc-link viewer (plan:
/// src/rnd/2026.09.08-abstract-doc-link-viewer-implementation-plan.md §5).
///
/// The parser is the piece that decides what is tappable, so its classification
/// surface is pinned here exhaustively — including the forms we deliberately
/// REFUSE to follow.
void main() {
  group( "classifyDocHref — modern doc-viewer form", () {
    test( "canonical /app/docs link resolves to the raw-content endpoint", () {
      final link = classifyDocHref(
        "/app/docs?path=lupin-mobile/src/rnd/2026.09.08-notes.md",
        label: "Open: notes",
      );

      expect( link.kind,     DocLinkKind.docs );
      expect( link.project,  "lupin-mobile" );
      expect( link.relPath,  "src/rnd/2026.09.08-notes.md" );
      expect( link.apiPath,  "/api/docs/file" );
      expect( link.query[ "path" ], "lupin-mobile/src/rnd/2026.09.08-notes.md" );
      expect( link.isFetchable, isTrue );
      expect( link.label,    "Open: notes" );
    } );

    test( "an already-resolved /api/docs/file href passes through", () {
      final link = classifyDocHref( "/api/docs/file?path=lupin/README.md" );

      expect( link.kind,    DocLinkKind.docs );
      expect( link.project, "lupin" );
      expect( link.relPath, "README.md" );
      expect( link.apiPath, "/api/docs/file" );
    } );

    test( "rawHref is preserved verbatim, never rewritten", () {
      const href = "/app/docs?path=lupin-mobile/README.md";
      expect( classifyDocHref( href ).rawHref, href );
    } );

    test( "a deep path keeps every segment after the project", () {
      final link = classifyDocHref( "/app/docs?path=lupin/src/cosa/rest/routers/docs_files.py" );

      expect( link.project, "lupin" );
      expect( link.relPath, "src/cosa/rest/routers/docs_files.py" );
    } );

    test( "percent-encoded paths are decoded before splitting", () {
      final link = classifyDocHref( "/app/docs?path=lupin-mobile%2Fsrc%2Frnd%2Fa%20b.md" );

      expect( link.kind,    DocLinkKind.docs );
      expect( link.project, "lupin-mobile" );
      expect( link.relPath, "src/rnd/a b.md" );
      // Query is handed to Dio DECODED — Dio re-encodes on the way out, so
      // pre-encoding here would double-encode.
      expect( link.query[ "path" ], "lupin-mobile/src/rnd/a b.md" );
    } );
  } );

  group( "classifyDocHref — io artifacts", () {
    test( "/api/io/file is fetchable and carries no project", () {
      final link = classifyDocHref( "/api/io/file?path=dr-a1b2c3d4-report.md" );

      expect( link.kind,        DocLinkKind.io );
      expect( link.project,     isNull );
      expect( link.relPath,     "dr-a1b2c3d4-report.md" );
      expect( link.apiPath,     "/api/io/file" );
      expect( link.isFetchable, isTrue );
    } );
  } );

  group( "classifyDocHref — external URLs", () {
    test( "https is external: tappable but not fetchable", () {
      final link = classifyDocHref( "https://pub.dev/packages/flutter_markdown_plus" );

      expect( link.kind,        DocLinkKind.external );
      expect( link.isFetchable, isFalse );
      expect( link.isTappable,  isTrue );
      expect( link.apiPath,     isEmpty );
    } );

    test( "http is external too", () {
      expect( classifyDocHref( "http://example.com/x" ).kind, DocLinkKind.external );
    } );
  } );

  group( "classifyDocHref — refused forms", () {
    test( "the RETIRED ?scope= form classifies unknown, and is NOT rewritten", () {
      // Rick 2026-09-08: modern format only. The backend answers 400 on `scope`,
      // so offering a tap here would offer a guaranteed failure.
      final link = classifyDocHref( "/app/docs?path=src/rnd/x.md&scope=lupin-mobile" );

      expect( link.kind,        DocLinkKind.unknown );
      expect( link.isFetchable, isFalse );
      expect( link.isTappable,  isFalse );
      expect( link.project,     isNull );
    } );

    test( "?scope= is refused even alongside a modern project-qualified path", () {
      final link = classifyDocHref( "/app/docs?path=lupin-mobile/README.md&scope=lupin-mobile" );
      expect( link.kind, DocLinkKind.unknown );
    } );

    test( "a docs link with no path parameter is unknown", () {
      expect( classifyDocHref( "/app/docs" ).kind,         DocLinkKind.unknown );
      expect( classifyDocHref( "/app/docs?path=" ).kind,   DocLinkKind.unknown );
    } );

    test( "a path with no project segment is unknown — we do not guess a project", () {
      expect( classifyDocHref( "/app/docs?path=README.md" ).kind, DocLinkKind.unknown );
    } );

    test( "a project with no remaining path is unknown", () {
      expect( classifyDocHref( "/app/docs?path=lupin-mobile/" ).kind, DocLinkKind.unknown );
    } );

    test( "a relative href is unknown — it carries no project context", () {
      expect( classifyDocHref( "./notes.md" ).kind,  DocLinkKind.unknown );
      expect( classifyDocHref( "notes.md" ).kind,    DocLinkKind.unknown );
    } );

    test( "an unrelated absolute app route is unknown", () {
      expect( classifyDocHref( "/app/queue" ).kind, DocLinkKind.unknown );
    } );

    test( "a mailto link is unknown, not external", () {
      expect( classifyDocHref( "mailto:someone@example.com" ).kind, DocLinkKind.unknown );
    } );
  } );

  group( "displayName", () {
    test( "is the basename of the target path", () {
      final link = classifyDocHref( "/app/docs?path=lupin-mobile/src/rnd/plan.md", label: "Open: plan" );
      expect( link.displayName, "plan.md" );
    } );

    test( "falls back to the label when there is no path", () {
      final link = classifyDocHref( "https://example.com", label: "the docs" );
      expect( link.displayName, "the docs" );
    } );
  } );

  group( "parseDocLinks", () {
    test( "null and empty abstracts yield no links", () {
      expect( parseDocLinks( null ), isEmpty );
      expect( parseDocLinks( "" ),   isEmpty );
    } );

    test( "prose with no links yields no links", () {
      expect( parseDocLinks( "**Verdict**: viable. No WebView required." ), isEmpty );
    } );

    test( "a single link inside surrounding prose is found", () {
      const abstract = """
**Verdict**: viable.

Plan: [Open: plan.md](/app/docs?path=lupin-mobile/src/rnd/plan.md)

No backend work.
""";
      final links = parseDocLinks( abstract );

      expect( links,                 hasLength( 1 ) );
      expect( links.first.kind,      DocLinkKind.docs );
      expect( links.first.label,     "Open: plan.md" );
      expect( links.first.relPath,   "src/rnd/plan.md" );
    } );

    test( "multiple links on one line stay separate", () {
      final links = parseDocLinks(
        "See [a](/app/docs?path=p/a.md) and [b](/app/docs?path=p/b.md)."
      );

      expect( links, hasLength( 2 ) );
      expect( links[ 0 ].relPath, "a.md" );
      expect( links[ 1 ].relPath, "b.md" );
    } );

    test( "mixed kinds are all returned, in document order", () {
      final links = parseDocLinks(
        "[doc](/app/docs?path=p/a.md) [ext](https://example.com) [old](/app/docs?path=a.md&scope=p)"
      );

      expect( links.map( ( l ) => l.kind ).toList(), [
        DocLinkKind.docs,
        DocLinkKind.external,
        DocLinkKind.unknown,
      ] );
    } );

    test( "an empty href is skipped entirely", () {
      expect( parseDocLinks( "[nothing]()" ), isEmpty );
    } );

    test( "a markdown image is not mistaken for a link target", () {
      // `![alt](src)` — the leading `!` is not consumed, but the inner
      // `[alt](src)` still matches; it must classify unknown, not fetchable.
      final links = parseDocLinks( "![diagram](assets/diagram.png)" );
      expect( links.every( ( l ) => !l.isFetchable ), isTrue );
    } );
  } );

  group( "hasFetchableDocLink — the badge predicate", () {
    test( "true when a docs link is present", () {
      expect(
        hasFetchableDocLink( "[x](/app/docs?path=lupin-mobile/README.md)" ),
        isTrue,
      );
    } );

    test( "true for an io artifact link", () {
      expect( hasFetchableDocLink( "[r](/api/io/file?path=report.md)" ), isTrue );
    } );

    test( "FALSE when the only link is external — the badge promises in-app content", () {
      expect( hasFetchableDocLink( "[site](https://example.com)" ), isFalse );
    } );

    test( "FALSE when the only link is the retired legacy form", () {
      expect(
        hasFetchableDocLink( "[old](/app/docs?path=x.md&scope=lupin-mobile)" ),
        isFalse,
      );
    } );

    test( "false for null, empty, and link-free prose", () {
      expect( hasFetchableDocLink( null ),             isFalse );
      expect( hasFetchableDocLink( "" ),               isFalse );
      expect( hasFetchableDocLink( "just **prose**" ), isFalse );
    } );

    test( "true when a fetchable link sits among unfetchable ones", () {
      expect(
        hasFetchableDocLink(
          "[ext](https://example.com) then [doc](/app/docs?path=p/a.md)"
        ),
        isTrue,
      );
    } );
  } );
}
