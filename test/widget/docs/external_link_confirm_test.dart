import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/abstract_body.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';

/// Q4 — leaving the app is deliberate: an external `http(s)` link in an abstract
/// asks before it launches.
///
/// This path shipped in `756ae43` with no coverage. Untested-but-shipped is the
/// worse state: it either works or silently does not, and nothing says which.

class _FakeDocRepository implements DocRepository {
  DocLink? lastRequested;

  @override
  Future<DocContent> fetch( DocLink link ) async {
    lastRequested = link;
    return const DocContent(
      kind: DocContentKind.markdown, mediaType: "text/markdown", text: "# doc",
    );
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

void main() {
  // url_launcher talks to the platform over a MethodChannel that does not exist
  // in a widget test, so we stand in for it and record what it was asked to do.
  const channel = MethodChannel( "plugins.flutter.io/url_launcher" );
  late List<MethodCall> launcherCalls;

  setUp( () {
    launcherCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler( channel, ( call ) async {
      launcherCalls.add( call );
      // `canLaunch` must answer true or launchUrl throws before it ever calls
      // through; `launch` answers true to report success.
      return true;
    } );
  } );

  tearDown( () {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler( channel, null );
  } );

  Future<void> pump( WidgetTester tester, String abstractText, _FakeDocRepository repo ) async {
    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: AbstractBody( abstractText: abstractText, repository: repo ),
      ),
    ) );
  }

  group( "external links ask before leaving the app", () {
    testWidgets( "tapping an external link raises a confirm naming the URL", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "See [pub](https://pub.dev/packages/dio)", repo );

      // The link sits INSIDE prose here, so the paragraph's centre is the word
      // "See", not the link. Tap the link's own text range.
      await tester.tapOnText( find.textRange.ofSubstring( "pub" ) );
      await tester.pumpAndSettle();

      expect( find.text( "Open outside the app?" ),          findsOneWidget );
      // The user is shown exactly where they are about to go.
      expect( find.text( "https://pub.dev/packages/dio" ),   findsOneWidget );
      expect( find.text( "Cancel" ),                         findsOneWidget );
      expect( find.text( "Open" ),                           findsOneWidget );
      // Nothing has launched yet.
      expect( launcherCalls,                                 isEmpty );
    } );

    testWidgets( "Cancel dismisses and launches NOTHING", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[pub](https://pub.dev/packages/dio)", repo );

      await tester.tap( find.textContaining( "pub" ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( "Cancel" ) );
      await tester.pumpAndSettle();

      expect( find.text( "Open outside the app?" ), findsNothing );
      expect( launcherCalls,                        isEmpty );
    } );

    testWidgets( "Open launches the URL externally", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[pub](https://pub.dev/packages/dio)", repo );

      await tester.tap( find.textContaining( "pub" ) );
      await tester.pumpAndSettle();
      await tester.tap( find.text( "Open" ) );
      await tester.pumpAndSettle();

      expect( launcherCalls, isNotEmpty );
      final launched = launcherCalls.map( ( c ) => c.arguments?.toString() ?? "" ).join( " " );
      expect( launched, contains( "pub.dev/packages/dio" ) );
    } );

    testWidgets( "an http link is confirmed too, not just https", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[site](http://example.com/x)", repo );

      await tester.tap( find.textContaining( "site" ) );
      await tester.pumpAndSettle();

      expect( find.text( "Open outside the app?" ), findsOneWidget );
    } );
  } );

  group( "the confirm belongs ONLY to external links", () {
    testWidgets( "a doc link opens in-app with NO confirm and NO launch", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[plan](/app/docs?path=lupin-mobile/src/rnd/plan.md)", repo );

      await tester.tap( find.textContaining( "plan" ) );
      await tester.pumpAndSettle();

      expect( find.text( "Open outside the app?" ), findsNothing );
      expect( find.byType( DocViewerScreen ),       findsOneWidget );
      expect( launcherCalls,                        isEmpty );
      expect( repo.lastRequested?.relPath,          "src/rnd/plan.md" );
    } );

    testWidgets( "an unknown link neither confirms, navigates, nor launches", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[old](/app/docs?path=x.md&scope=lupin-mobile)", repo );

      await tester.tap( find.textContaining( "old" ) );
      await tester.pumpAndSettle();

      expect( find.text( "Open outside the app?" ), findsNothing );
      expect( find.byType( DocViewerScreen ),       findsNothing );
      expect( launcherCalls,                        isEmpty );
      expect( repo.lastRequested,                   isNull );
    } );

    testWidgets( "a mailto link is inert — we do not hand it to the launcher", ( tester ) async {
      final repo = _FakeDocRepository();
      await pump( tester, "[mail](mailto:someone@example.com)", repo );

      await tester.tap( find.textContaining( "mail" ) );
      await tester.pumpAndSettle();

      expect( launcherCalls, isEmpty );
    } );
  } );
}
