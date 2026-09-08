import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';

/// P2 — the viewer renders each content kind, and surfaces failures in the
/// server's own words (plan §8, items 6-7).

/// A real 1x1 transparent PNG. Image.memory decodes its bytes for real, so
/// arbitrary filler would fail the codec rather than the assertion under test.
final List<int> _onePixelPng = base64Decode(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
  "YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
);

class _FakeDocRepository implements DocRepository {
  final DocContent? content;
  final Object?     error;
  int               fetchCount = 0;

  _FakeDocRepository( { this.content, this.error } );

  @override
  Future<DocContent> fetch( DocLink link ) async {
    fetchCount++;
    if ( error != null ) throw error!;
    return content!;
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

void main() {
  final link = classifyDocHref(
    "/app/docs?path=lupin-mobile/src/rnd/plan.md",
    label: "Open: plan.md",
  );

  Future<void> pump( WidgetTester tester, _FakeDocRepository repo ) async {
    await tester.pumpWidget( MaterialApp(
      home: DocViewerScreen( link: link, repository: repo ),
    ) );
    await tester.pumpAndSettle();
  }

  group( "render branches", () {
    testWidgets( "markdown content renders with the Markdown widget", ( tester ) async {
      await pump( tester, _FakeDocRepository(
        content: const DocContent(
          kind: DocContentKind.markdown, mediaType: "text/markdown", text: "# Hello",
        ),
      ) );

      expect( find.byKey( const Key( TestKeys.docViewerMarkdown ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.docViewerSource ) ),   findsNothing );
    } );

    testWidgets( "source content renders monospaced, not as markdown", ( tester ) async {
      await pump( tester, _FakeDocRepository(
        content: const DocContent(
          kind: DocContentKind.source, mediaType: "text/x-python", text: "# not a heading\nx = 1",
        ),
      ) );

      expect( find.byKey( const Key( TestKeys.docViewerSource ) ),   findsOneWidget );
      expect( find.byKey( const Key( TestKeys.docViewerMarkdown ) ), findsNothing );
    } );

    testWidgets( "the app bar names the target file", ( tester ) async {
      await pump( tester, _FakeDocRepository(
        content: const DocContent(
          kind: DocContentKind.markdown, mediaType: "text/markdown", text: "x",
        ),
      ) );

      expect( find.text( "plan.md" ), findsOneWidget );
    } );

    testWidgets( "a share action is offered for text content", ( tester ) async {
      await pump( tester, _FakeDocRepository(
        content: const DocContent(
          kind: DocContentKind.markdown, mediaType: "text/markdown", text: "x",
        ),
      ) );

      expect( find.byKey( const Key( TestKeys.docViewerShareButton ) ), findsOneWidget );
    } );

    testWidgets( "no share action for an image, which has no text to write", ( tester ) async {
      await pump( tester, _FakeDocRepository(
        content: DocContent(
          kind: DocContentKind.image, mediaType: "image/png", bytes: _onePixelPng,
        ),
      ) );

      expect( find.byKey( const Key( TestKeys.docViewerShareButton ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.docViewerImage ) ),       findsOneWidget );
    } );
  } );

  group( "AC-7 — refusals are shown in the server's own words", () {
    testWidgets( "a credential refusal is displayed verbatim", ( tester ) async {
      const detail = "Refused: this file's CONTENT is credential material "
                     "(service-account key, OAuth token, or private key).";
      await pump( tester, _FakeDocRepository(
        error: const DocApiException( detail, statusCode: 400 ),
      ) );

      expect( find.byKey( const Key( TestKeys.docViewerError ) ), findsOneWidget );
      expect( find.textContaining( "credential material" ),       findsOneWidget );
    } );

    testWidgets( "an unreadable-file error keeps its distinct wording", ( tester ) async {
      // This is a DIFFERENT fact from the credential refusal and must not be
      // flattened into it — one sends you to the file, the other to the mount.
      const detail = "Error reading file: it could not be read or decoded.";
      await pump( tester, _FakeDocRepository(
        error: const DocApiException( detail, statusCode: 500 ),
      ) );

      expect( find.textContaining( "could not be read" ), findsOneWidget );
      expect( find.textContaining( "credential" ),        findsNothing );
    } );

    testWidgets( "retry re-issues the fetch", ( tester ) async {
      final repo = _FakeDocRepository( error: const DocApiException( "boom", statusCode: 500 ) );
      await pump( tester, repo );

      expect( repo.fetchCount, 1 );

      await tester.tap( find.text( "Try again" ) );
      await tester.pumpAndSettle();

      expect( repo.fetchCount, 2 );
    } );
  } );
}
