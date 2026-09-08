import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';

/// P2 — content-type dispatch (plan §6).
///
/// The endpoint is polymorphic, so the dispatch is the logic worth pinning.
/// Exercised through the static `toContent` seam so no live Dio is needed.
void main() {
  List<int> b( String s ) => utf8.encode( s );

  group( "content-type dispatch", () {
    test( "text/markdown renders as markdown", () {
      final c = DocRepository.toContent( "text/markdown; charset=utf-8", b( "# Title" ) );

      expect( c.kind,      DocContentKind.markdown );
      expect( c.text,      "# Title" );
      expect( c.mediaType, "text/markdown; charset=utf-8" );
    } );

    test( "text/html renders as html", () {
      final c = DocRepository.toContent( "text/html; charset=utf-8", b( "<p>hi</p>" ) );
      expect( c.kind, DocContentKind.html );
    } );

    test( "image/png retains raw bytes and decodes no text", () {
      final bytes = [ 0x89, 0x50, 0x4E, 0x47 ];
      final c     = DocRepository.toContent( "image/png", bytes );

      expect( c.kind,  DocContentKind.image );
      expect( c.bytes, bytes );
      expect( c.text,  isNull );
    } );

    test( "python source is NOT fed to the markdown renderer", () {
      // `# comment` would become an H1 heading if this dispatched to markdown.
      final c = DocRepository.toContent( "text/x-python; charset=utf-8", b( "# a comment\nx = 1" ) );

      expect( c.kind, DocContentKind.source );
      expect( c.text, "# a comment\nx = 1" );
    } );

    test( "yaml, shell, and plain text all take the source branch", () {
      for ( final mt in [
        "text/yaml; charset=utf-8",
        "text/x-shellscript; charset=utf-8",
        "text/plain; charset=utf-8",
        "text/x-sql; charset=utf-8",
      ] ) {
        expect( DocRepository.toContent( mt, b( "x" ) ).kind, DocContentKind.source,
            reason: "$mt should render as source" );
      }
    } );

    test( "media type casing does not change the branch", () {
      expect(
        DocRepository.toContent( "TEXT/MARKDOWN; CHARSET=UTF-8", b( "# x" ) ).kind,
        DocContentKind.markdown,
      );
    } );

    test( "an unknown media type falls back to source, never to an error", () {
      expect( DocRepository.toContent( "", b( "x" ) ).kind, DocContentKind.source );
    } );

    test( "malformed UTF-8 degrades to replacement characters instead of throwing", () {
      final c = DocRepository.toContent( "text/markdown", [ 0xC3, 0x28 ] );

      expect( c.kind, DocContentKind.markdown );
      expect( c.text, isNotNull );
    } );
  } );

  group( "directory listings", () {
    test( "a JSON body carrying entries is a directory, not a document", () {
      final body = jsonEncode( {
        "path"   : "src/rnd",
        "scope"  : "lupin-mobile",
        "parent" : "src",
        "entries": [
          { "name": "a.md",  "path": "src/rnd/a.md", "type": "file",      "size": 120 },
          { "name": "sub",   "path": "src/rnd/sub",  "type": "directory" },
        ],
      } );

      final c = DocRepository.toContent( "application/json", b( body ) );

      expect( c.kind,            DocContentKind.directory );
      expect( c.listing,         isNotNull );
      expect( c.listing!.scope,  "lupin-mobile" );
      expect( c.listing!.parent, "src" );
      expect( c.listing!.entries, hasLength( 2 ) );
      expect( c.listing!.entries[ 0 ].isDirectory, isFalse );
      expect( c.listing!.entries[ 0 ].sizeBytes,   120 );
      expect( c.listing!.entries[ 1 ].isDirectory, isTrue );
    } );

    test( "a real .json DOCUMENT is source, not a directory", () {
      // Same media type, different shape — shape decides.
      final c = DocRepository.toContent( "application/json", b( '{"model":"gpt-4"}' ) );

      expect( c.kind,    DocContentKind.source );
      expect( c.listing, isNull );
      expect( c.text,    '{"model":"gpt-4"}' );
    } );

    test( "a JSON array is source, not a listing", () {
      expect(
        DocRepository.toContent( "application/json", b( "[1,2,3]" ) ).kind,
        DocContentKind.source,
      );
    } );

    test( "a listing with no parent (scope root) parses cleanly", () {
      final body = jsonEncode( { "path": "", "scope": "lupin", "entries": [] } );
      final c    = DocRepository.toContent( "application/json", b( body ) );

      expect( c.kind,            DocContentKind.directory );
      expect( c.listing!.parent, isNull );
      expect( c.listing!.entries, isEmpty );
    } );
  } );

  group( "DocApiException", () {
    test( "carries the status code and message", () {
      const e = DocApiException( "Refused: credential material", statusCode: 400 );

      expect( e.message,    "Refused: credential material" );
      expect( e.statusCode, 400 );
      expect( e.toString(), contains( "400" ) );
    } );
  } );
}
