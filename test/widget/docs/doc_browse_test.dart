import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';

/// Row 61ecfb22 — Download, 📁 Folder, the listing and Roots, driven through
/// the real viewer. The fake answers by the path it was asked for, so every
/// assertion on `asked` is an assertion on what would have gone on the wire.
class _Repo implements DocRepository {
  final Map<String, DocContent> byPath;
  final List<String> asked = [];
  int scopeReads = 0;

  _Repo( this.byPath );

  @override
  Future<DocContent> fetch( DocLink link ) async {
    final path = link.query[ "path" ]!;
    asked.add( path );
    final c = byPath[ path ];
    if ( c == null ) throw DocApiException( "Path not found: $path", statusCode: 404 );
    return c;
  }

  @override
  Future<List<DocScope>> fetchScopes() async {
    scopeReads++;
    return const [ DocScope( name: "lupin", allowedPrefixes: [ "src/rnd/" ] ) ];
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

DocContent _md( String text ) => DocContent(
  kind: DocContentKind.markdown, mediaType: "text/markdown", text: text, bytes: utf8.encode( text ),
);

DocContent _dir( String scope, String path, List<DocDirectoryEntry> entries, { String? parent } ) =>
    DocContent(
      kind     : DocContentKind.directory,
      mediaType: "application/json",
      listing  : DocDirectoryListing( scope: scope, path: path, parent: parent, entries: entries ),
    );

final _file = classifyDocHref( "/app/docs?path=lupin-mobile/src/rnd/plan.md", label: "Open: plan.md" );

_Repo _world() => _Repo( {
  "lupin-mobile/src/rnd/plan.md" : _md( "# Plan" ),
  "lupin-mobile/src/rnd"         : _dir( "lupin-mobile", "src/rnd", const [
    DocDirectoryEntry( name: "old", path: "src/rnd/old", isDirectory: true ),
    DocDirectoryEntry( name: "plan.md", path: "src/rnd/plan.md", isDirectory: false, sizeBytes: 2048 ),
  ], parent: "src" ),
  "lupin-mobile/src"             : _dir( "lupin-mobile", "src", const [] ),
  "lupin/src/rnd"                : _dir( "lupin", "src/rnd", const [] ),
  "report.pdf"                   : const DocContent(
    kind: DocContentKind.binary, mediaType: "application/pdf", bytes: [ 1, 2, 3 ] ),
} );

Future<_Repo> _pump( WidgetTester tester, { DocLink? link } ) async {
  final repo = _world();
  await tester.pumpWidget( MaterialApp(
    home: DocViewerScreen( link: link ?? _file, repository: repo ),
  ) );
  await tester.pumpAndSettle();
  return repo;
}

Finder _key( String k ) => find.byKey( Key( k ) );

void main() {
  group( "a FILE view offers Download and Folder", () {
    testWidgets( "both buttons sit on a file", ( tester ) async {
      await _pump( tester );
      expect( _key( TestKeys.docViewerDownloadButton ), findsOneWidget );
      expect( _key( TestKeys.docViewerFolderButton ),   findsOneWidget );
    } );

    testWidgets( "content handed in by the caller has neither — there is no file", ( tester ) async {
      await tester.pumpWidget( MaterialApp(
        home: DocViewerScreen( content: _md( "an abstract" ), title: "Abstract" ),
      ) );
      await tester.pumpAndSettle();
      expect( _key( TestKeys.docViewerDownloadButton ), findsNothing );
      expect( _key( TestKeys.docViewerFolderButton ),   findsNothing );
    } );

    testWidgets( "a PDF says there is no preview and still offers Download", ( tester ) async {
      await _pump( tester, link: classifyDocHref( "/api/io/file?path=report.pdf" ) );
      expect( _key( TestKeys.docViewerNoPreview ),      findsOneWidget );
      expect( _key( TestKeys.docViewerDownloadButton ), findsOneWidget );
    } );
  } );

  group( "📁 Folder opens the file's folder, in place", () {
    testWidgets( "asks for the folder and renders it as a listing, not JSON", ( tester ) async {
      final repo = await _pump( tester );
      await tester.tap( _key( TestKeys.docViewerFolderButton ) );
      await tester.pumpAndSettle();

      expect( repo.asked.last, "lupin-mobile/src/rnd" );
      expect( _key( TestKeys.docListing ), findsOneWidget );
      expect( _key( "${TestKeys.docListingEntryPrefix}old" ), findsOneWidget );
      expect( find.text( "2.0 KB" ), findsOneWidget );
      expect( find.text( "lupin-mobile/src/rnd" ), findsOneWidget, reason: "the title names the folder" );
      // A listing is not a file: no Download, no Folder.
      expect( _key( TestKeys.docViewerDownloadButton ), findsNothing );
      expect( _key( TestKeys.docViewerFolderButton ),   findsNothing );
    } );

    testWidgets( "a tapped entry opens the file; Back returns to the listing, then the start",
        ( tester ) async {
      final repo = await _pump( tester );
      await tester.tap( _key( TestKeys.docViewerFolderButton ) );
      await tester.pumpAndSettle();
      await tester.tap( _key( "${TestKeys.docListingEntryPrefix}plan.md" ) );
      await tester.pumpAndSettle();

      expect( repo.asked.last, "lupin-mobile/src/rnd/plan.md" );
      expect( _key( TestKeys.docViewerMarkdown ), findsOneWidget );

      await tester.tap( _key( TestKeys.docViewerBackButton ) );
      await tester.pumpAndSettle();
      expect( _key( TestKeys.docListing ), findsOneWidget );

      await tester.tap( _key( TestKeys.docViewerBackButton ) );
      await tester.pumpAndSettle();
      expect( _key( TestKeys.docViewerBackButton ), findsNothing );
      expect( find.text( "plan.md" ), findsOneWidget, reason: "back at the file it opened on" );
      expect( _key( TestKeys.docViewerMarkdown ), findsOneWidget );
    } );

    testWidgets( "Up follows the server's parent", ( tester ) async {
      final repo = await _pump( tester );
      await tester.tap( _key( TestKeys.docViewerFolderButton ) );
      await tester.pumpAndSettle();
      await tester.tap( _key( TestKeys.docListingUp ) );
      await tester.pumpAndSettle();

      expect( repo.asked.last, "lupin-mobile/src" );
      expect( _key( TestKeys.docListingEmpty ), findsOneWidget );
      expect( _key( TestKeys.docListingUp ), findsNothing, reason: "the server said no parent" );
    } );
  } );

  group( "Roots", () {
    testWidgets( "folded and unfetched until opened, then io plus each allowed folder",
        ( tester ) async {
      final repo = await _pump( tester );
      await tester.tap( _key( TestKeys.docViewerFolderButton ) );
      await tester.pumpAndSettle();
      expect( repo.scopeReads, 0, reason: "the roots cost a request nobody asked for yet" );

      await tester.tap( _key( TestKeys.docRootsPanel ) );
      await tester.pumpAndSettle();
      expect( repo.scopeReads, 1 );
      expect( _key( "${TestKeys.docRootPrefix}io" ), findsOneWidget );

      await tester.tap( _key( "${TestKeys.docRootPrefix}lupin/src/rnd" ) );
      await tester.pumpAndSettle();
      expect( repo.asked.last, "lupin/src/rnd" );
    } );
  } );
}
