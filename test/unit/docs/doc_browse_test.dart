import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_directory_view.dart';

import '../_helpers/stub_dio.dart';

/// Row 61ecfb22 — browsing, Download and Roots, the data half.
void main() {
  List<int> b( String s ) => utf8.encode( s );

  group( "docLinkFor — the browser builds its own links", () {
    test( "a scope-relative path becomes <scope>/<rel> on the docs endpoint", () {
      final l = docLinkFor( "lupin-mobile", "src/rnd" );
      expect( l.kind,    DocLinkKind.docs );
      expect( l.apiPath, "/api/docs/file" );
      expect( l.query,   { "path": "lupin-mobile/src/rnd" } );
      expect( l.project, "lupin-mobile" );
      expect( l.relPath, "src/rnd" );
    } );

    test( "a scope root is the scope name alone", () {
      expect( docLinkFor( "lupin-mobile", "" ).query, { "path": "lupin-mobile" } );
    } );

    test( "io goes to the io endpoint, io-relative, with '.' for its root", () {
      final l = docLinkFor( ioScope, "reports/a.pdf" );
      expect( l.kind,    DocLinkKind.io );
      expect( l.apiPath, "/api/io/file" );
      expect( l.query,   { "path": "reports/a.pdf" } );
      expect( docLinkFor( ioScope, "" ).query, { "path": "." },
          reason: "the io endpoint requires a non-empty path" );
    } );
  } );

  group( "folderLinkFor — the 📁 Folder button", () {
    test( "a nested docs file opens its own folder", () {
      final file = classifyDocHref( "/app/docs?path=lupin-mobile/src/rnd/plan.md" );
      expect( folderLinkFor( file )!.query, { "path": "lupin-mobile/src/rnd" } );
    } );

    test( "a top-level file opens the scope root", () {
      final file = classifyDocHref( "/app/docs?path=lupin-mobile/README.md" );
      expect( folderLinkFor( file )!.query, { "path": "lupin-mobile" } );
    } );

    test( "an io file opens its io folder", () {
      final file = classifyDocHref( "/api/io/file?path=podcasts/ep1/script.md" );
      expect( folderLinkFor( file )!.query, { "path": "podcasts/ep1" } );
      final top = classifyDocHref( "/api/io/file?path=notes.md" );
      expect( folderLinkFor( top )!.query, { "path": "." } );
    } );

    test( "an external link has no folder", () {
      expect( folderLinkFor( classifyDocHref( "https://example.com/x.md" ) ), isNull );
    } );
  } );

  group( "listings in the server's REAL shape", () {
    // Mr. Radio, 2026-09-24: {kind, scope, path, parent, entries:[{name, kind,
    // size, rel_path, view_url}]}. The old parser read `type` and `path` only.
    final realListing = jsonEncode( {
      "kind"   : "directory",
      "scope"  : "io",
      "path"   : "podcasts",
      "parent" : null,
      "entries": [
        { "name": "ep1", "kind": "directory", "size": null, "rel_path": "podcasts/ep1",
          "view_url": "/app/docs?path=io/podcasts/ep1" },
        { "name": "a.mp3", "kind": "file", "size": 2048, "rel_path": "podcasts/a.mp3",
          "view_url": "/app/audio?path=podcasts%2Fa.mp3" },
      ],
    } );

    test( "reads kind and rel_path", () {
      final c = DocRepository.toContent( "application/json", b( realListing ) );
      expect( c.kind, DocContentKind.directory );
      final e = c.listing!.entries;
      expect( e[ 0 ].isDirectory, isTrue );
      expect( e[ 0 ].path,        "podcasts/ep1" );
      expect( e[ 1 ].isDirectory, isFalse );
      expect( e[ 1 ].path,        "podcasts/a.mp3",
          reason: "rel_path, never the view_url, which is a web audio page" );
    } );

    test( "a .json FILE with an entries key but another kind is a document", () {
      final body = jsonEncode( { "kind": "report", "entries": [] } );
      expect( DocRepository.toContent( "application/json", b( body ) ).kind,
          DocContentKind.source );
    } );
  } );

  group( "Download keeps the original bytes", () {
    test( "markdown keeps its SOURCE bytes, not a render", () {
      final bytes = b( "# Title\nbody" );
      final c     = DocRepository.toContent( "text/markdown; charset=utf-8", bytes );
      expect( c.bytes, bytes );
    } );

    test( "PDF, audio, video and office files are binary, never decoded as text", () {
      for ( final mt in [ "application/pdf", "audio/mpeg", "audio/wav", "video/mp4",
                          "application/vnd.openxmlformats-officedocument.presentationml.presentation" ] ) {
        final c = DocRepository.toContent( mt, [ 0x25, 0x50, 0xFF ] );
        expect( c.kind,  DocContentKind.binary, reason: mt );
        expect( c.text,  isNull,                reason: mt );
        expect( c.bytes, [ 0x25, 0x50, 0xFF ],  reason: mt );
      }
    } );
  } );

  group( "fetchScopes and the Roots panel", () {
    test( "reads GET /api/docs/scopes", () async {
      final adapter = StubAdapter();
      adapter.handlers[ "GET /api/docs/scopes" ] = ( _ ) => jsonBody( {
        "scopes": [
          { "name": "lupin", "root": "/x", "allowed_prefixes": [ "src/rnd/", "docs/" ] },
          { "name": "lupin-mobile", "root": "/y", "allowed_prefixes": [ "*" ] },
        ],
      } );
      final scopes = await DocRepository( makeDio( adapter ) ).fetchScopes();
      expect( scopes.map( ( s ) => s.name ), [ "lupin", "lupin-mobile" ] );
      expect( scopes[ 0 ].allowedPrefixes, [ "src/rnd/", "docs/" ] );
    } );

    test( "a refused scopes read carries the server's words", () async {
      final adapter = StubAdapter();
      adapter.handlers[ "GET /api/docs/scopes" ] =
          ( _ ) => jsonBody( { "detail": "Not authenticated" }, status: 401 );
      await expectLater(
        DocRepository( makeDio( adapter ) ).fetchScopes(),
        throwsA( isA<DocApiException>().having( ( e ) => e.message, "message", "Not authenticated" ) ),
      );
    } );

    test( "roots: io first, each allowed folder, a wildcard scope at its root", () {
      final roots = rootsFor( const [
        DocScope( name: "lupin",        allowedPrefixes: [ "src/rnd/", "docs/" ] ),
        DocScope( name: "lupin-mobile", allowedPrefixes: [ "*" ] ),
        DocScope( name: "empty",        allowedPrefixes: [] ),
      ] );
      expect( roots.map( ( r ) => r.label ),
          [ "io", "lupin/src/rnd", "lupin/docs", "lupin-mobile", "empty" ] );
      expect( roots[ 0 ].link.query, { "path": "." } );
      expect( roots[ 1 ].link.query, { "path": "lupin/src/rnd" } );
      expect( roots[ 3 ].link.query, { "path": "lupin-mobile" } );
    } );
  } );
}
