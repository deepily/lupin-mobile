import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/abstract_body.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_split_host.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';

/// The abstract, disclosed on request (Rick 2026-09-18: "the whole idea
/// behind using abstracts as a notion is progressive disclosure").
///
/// The bubble shows one compact row and never the abstract's text. A tap opens
/// the whole abstract in the document viewer, where it renders as markdown and
/// its links are live. Replaces P3's inline render, badge and collapse.

/// A DocRepository that answers from memory, so no server is involved.
class _FakeDocRepository implements DocRepository {
  final DocContent? content;
  DocLink?          lastRequested;

  _FakeDocRepository( { this.content } );

  @override
  Future<DocContent> fetch( DocLink link ) async {
    lastRequested = link;
    return content ??
        const DocContent(
          kind      : DocContentKind.markdown,
          mediaType : "text/markdown",
          text      : "# Fetched document",
        );
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    String? abstractText, {
    DocRepository? repository,
  } ) async {
    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: AbstractBody(
          abstractText : abstractText,
          repository   : repository ?? _FakeDocRepository(),
        ),
      ),
    ) );
  }

  Future<void> openIt( WidgetTester tester ) async {
    await tester.tap( find.byKey( const Key( TestKeys.abstractOpenButton ) ) );
    await tester.pumpAndSettle();
  }

  // Twelve source lines, so "the whole abstract" is a real claim.
  final long = [
    "# Twelve lines",
    for ( var i = 2; i <= 11; i++ ) "Line $i of the abstract.",
    "The very last line.",
  ].join( "\n" );

  group( "the conditional render", () {
    testWidgets( "a null abstract renders nothing at all", ( tester ) async {
      await pump( tester, null );

      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsNothing );
    } );

    testWidgets( "an empty abstract renders nothing at all", ( tester ) async {
      await pump( tester, "" );

      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsNothing );
    } );
  } );

  group( "progressive disclosure: the bubble never renders the abstract", () {
    testWidgets( "a present abstract is one tappable row, with none of its text", ( tester ) async {
      await pump( tester, "**The secret sentence** and a table:\n\n| a | b |\n|---|---|\n| 1 | 2 |" );

      expect( find.byKey( const Key( TestKeys.abstractOpenButton ) ), findsOneWidget );
      expect( find.text( "Abstract" ),                                 findsOneWidget );
      expect( find.byType( MarkdownBody ),                             findsNothing );
      expect( find.textContaining( "secret sentence" ),                findsNothing );
    } );

    testWidgets( "an abstract with a doc link says so on the row", ( tester ) async {
      await pump( tester, "See [plan](/app/docs?path=lupin-mobile/src/rnd/plan.md)" );

      expect( find.text( "Abstract · has a document" ), findsOneWidget );
      expect( find.textContaining( "plan" ),            findsNothing );
    } );

    testWidgets( "an external-only link does not count as a document", ( tester ) async {
      await pump( tester, "See [pub](https://pub.dev/packages/dio)" );

      expect( find.text( "Abstract" ), findsOneWidget );
    } );
  } );

  group( "a tap opens the WHOLE abstract in the viewer", () {
    testWidgets( "as a page titled Abstract, all of it, with nothing fetched", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, long, repository: repo );

      await openIt( tester );

      expect( find.byType( DocViewerScreen ),                       findsOneWidget );
      expect( find.byKey( const Key( TestKeys.docViewerMarkdown ) ), findsOneWidget );
      expect( find.text( "Abstract" ),                              findsOneWidget, reason: "the viewer's title" );
      expect( find.textContaining( "The very last line." ),         findsOneWidget );
      expect( repo.lastRequested, isNull, reason: "the abstract is in hand; nothing to fetch" );
    } );

    testWidgets( "inside a split host, it opens in the split instead of a new page", ( tester ) async {
      await tester.pumpWidget( MaterialApp(
        home: Scaffold(
          body: DocSplitHost(
            repository : () => _FakeDocRepository(),
            child      : AbstractBody( abstractText: long, repository: _FakeDocRepository() ),
          ),
        ),
      ) );

      await openIt( tester );

      expect( tester.state<DocSplitHostState>( find.byType( DocSplitHost ) ).showsText, isTrue );
      expect( find.byKey( const Key( TestKeys.docPanel ) ),     findsOneWidget );
      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsOneWidget,
          reason: "the bubble's row is still there beside the viewer" );
    } );
  } );

  group( "links inside the opened abstract are live", () {
    testWidgets( "a doc link opens that document and requests the right path", ( tester ) async {
      final repo = _FakeDocRepository(
        content: const DocContent( kind: DocContentKind.markdown, mediaType: "text/markdown", text: "# The fetched heading" ),
      );
      await pump( tester, "[Open: plan.md](/app/docs?path=lupin-mobile/src/rnd/plan.md)", repository: repo );
      await openIt( tester );

      await tester.tap( find.textContaining( "Open: plan.md" ) );
      await tester.pumpAndSettle();

      expect( repo.lastRequested!.project, "lupin-mobile" );
      expect( repo.lastRequested!.relPath, "src/rnd/plan.md" );
      expect( repo.lastRequested!.apiPath, "/api/docs/file" );
      expect( find.textContaining( "The fetched heading" ), findsOneWidget );
    } );

    testWidgets( "in the split, a doc link REPLACES the abstract in the same half", ( tester ) async {
      final repo = _FakeDocRepository();
      await tester.pumpWidget( MaterialApp(
        home: Scaffold(
          body: DocSplitHost(
            repository : () => repo,
            child      : AbstractBody(
              abstractText : "[Open: plan.md](/app/docs?path=lupin-mobile/src/rnd/plan.md)",
              repository   : repo,
            ),
          ),
        ),
      ) );
      await openIt( tester );

      await tester.tap( find.textContaining( "Open: plan.md" ) );
      await tester.pumpAndSettle();

      final host = tester.state<DocSplitHostState>( find.byType( DocSplitHost ) );
      expect( host.showsText,          isFalse );
      expect( host.link!.relPath,      "src/rnd/plan.md" );
      expect( find.byType( DocViewerScreen ), findsOneWidget, reason: "one half, not a stack of panels" );
    } );

    testWidgets( "a retired legacy link does NOT navigate", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[old](/app/docs?path=x.md&scope=p)", repository: repo );
      await openIt( tester );

      await tester.tap( find.textContaining( "old" ) );
      await tester.pumpAndSettle();

      expect( repo.lastRequested, isNull );
    } );
  } );
}
