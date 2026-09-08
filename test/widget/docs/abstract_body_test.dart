import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/abstract_body.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';

/// P3 — the abstract renders inline, conditionally, with a badge and live links.
///
/// These are the acceptance criteria from the plan (§8, items 1-4) expressed as
/// tests.

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
    int collapsedMaxLines = 8,
  } ) async {
    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: AbstractBody(
          abstractText      : abstractText,
          repository        : repository ?? _FakeDocRepository(),
          collapsedMaxLines : collapsedMaxLines,
        ),
      ),
    ) );
  }

  group( "AC-1 — the conditional render", () {
    testWidgets( "a null abstract renders nothing at all", ( tester ) async {
      await pump( tester, null );

      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsNothing );
      expect( find.byType( MarkdownBody ),                      findsNothing );
    } );

    testWidgets( "an empty abstract renders nothing at all", ( tester ) async {
      await pump( tester, "" );

      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsNothing );
    } );

    testWidgets( "a present abstract renders the card body", ( tester ) async {
      await pump( tester, "Some prose." );

      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsOneWidget );
      expect( find.byType( MarkdownBody ),                      findsOneWidget );
    } );
  } );

  group( "AC-2 — markdown actually formats", () {
    testWidgets( "prose goes through the markdown renderer, not a plain Text", ( tester ) async {
      await pump( tester, "**bold** and `code`" );

      expect( find.byType( MarkdownBody ), findsOneWidget );
    } );

    testWidgets( "a bulleted list renders", ( tester ) async {
      await pump( tester, "- first\n- second\n- third" );

      expect( find.byType( MarkdownBody ), findsOneWidget );
      expect( tester.takeException(),      isNull );
    } );

    testWidgets( "a table renders without throwing", ( tester ) async {
      await pump( tester, "| a | b |\n|---|---|\n| 1 | 2 |" );

      expect( find.byType( MarkdownBody ), findsOneWidget );
      expect( tester.takeException(),      isNull );
    } );

    testWidgets( "headings render without throwing", ( tester ) async {
      await pump( tester, "# Heading\n\nbody text" );

      expect( tester.takeException(), isNull );
    } );
  } );

  group( "AC-3 — the document badge", () {
    testWidgets( "appears when the abstract carries a doc link", ( tester ) async {
      await pump( tester, "See [plan](/app/docs?path=lupin-mobile/src/rnd/plan.md)" );

      expect( find.byKey( const Key( TestKeys.abstractDocBadge ) ), findsOneWidget );
    } );

    testWidgets( "is ABSENT for a link-free abstract", ( tester ) async {
      await pump( tester, "Just **prose**, no links." );

      expect( find.byKey( const Key( TestKeys.abstractDocBadge ) ), findsNothing );
    } );

    testWidgets( "is ABSENT when the only link is external", ( tester ) async {
      // The badge promises in-app content; an external URL is not that.
      await pump( tester, "See [pub](https://pub.dev/packages/dio)" );

      expect( find.byKey( const Key( TestKeys.abstractDocBadge ) ), findsNothing );
    } );

    testWidgets( "is ABSENT when the only link is the retired legacy form", ( tester ) async {
      await pump( tester, "See [old](/app/docs?path=x.md&scope=lupin-mobile)" );

      expect( find.byKey( const Key( TestKeys.abstractDocBadge ) ), findsNothing );
    } );
  } );

  group( "AC-4 — tapping a doc link opens the viewer", () {
    testWidgets( "tap pushes DocViewerScreen and requests the right path", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump(
        tester,
        "[Open: plan.md](/app/docs?path=lupin-mobile/src/rnd/plan.md)",
        repository: repo,
      );

      await tester.tap( find.textContaining( "Open: plan.md" ) );
      await tester.pumpAndSettle();

      expect( find.byType( DocViewerScreen ),                    findsOneWidget );
      expect( find.byKey( const Key( TestKeys.docViewerScreen ) ), findsOneWidget );
      expect( repo.lastRequested,                                isNotNull );
      expect( repo.lastRequested!.project,                       "lupin-mobile" );
      expect( repo.lastRequested!.relPath,                       "src/rnd/plan.md" );
      expect( repo.lastRequested!.apiPath,                       "/api/docs/file" );
    } );

    testWidgets( "the fetched markdown is rendered in the viewer", ( tester ) async {
      final repo = _FakeDocRepository(
        content: const DocContent(
          kind      : DocContentKind.markdown,
          mediaType : "text/markdown",
          text      : "# The fetched heading",
        ),
      );
      await pump( tester, "[doc](/app/docs?path=p/a.md)", repository: repo );

      await tester.tap( find.textContaining( "doc" ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.docViewerMarkdown ) ), findsOneWidget );
    } );

    testWidgets( "a retired legacy link does NOT navigate", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[old](/app/docs?path=x.md&scope=p)", repository: repo );

      await tester.tap( find.textContaining( "old" ) );
      await tester.pumpAndSettle();

      expect( find.byType( DocViewerScreen ), findsNothing );
      expect( repo.lastRequested,             isNull );
    } );
  } );

  group( "Q2 — long abstracts collapse", () {
    const long = "l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11\nl12";

    testWidgets( "a long abstract offers Show more", ( tester ) async {
      await pump( tester, long, collapsedMaxLines: 4 );

      expect( find.byKey( const Key( TestKeys.abstractExpandToggle ) ), findsOneWidget );
      expect( find.text( "Show more" ),                                findsOneWidget );
    } );

    testWidgets( "a short abstract offers no toggle", ( tester ) async {
      await pump( tester, "one\ntwo", collapsedMaxLines: 8 );

      expect( find.byKey( const Key( TestKeys.abstractExpandToggle ) ), findsNothing );
    } );

    testWidgets( "the toggle flips to Show less and back", ( tester ) async {
      await pump( tester, long, collapsedMaxLines: 4 );

      await tester.tap( find.byKey( const Key( TestKeys.abstractExpandToggle ) ) );
      await tester.pumpAndSettle();
      expect( find.text( "Show less" ), findsOneWidget );

      await tester.tap( find.byKey( const Key( TestKeys.abstractExpandToggle ) ) );
      await tester.pumpAndSettle();
      expect( find.text( "Show more" ), findsOneWidget );
    } );
  } );
}
