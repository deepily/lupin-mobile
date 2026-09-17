/// Rows 2416d2c5 / e0843a8a — the 50/50 split, for real this time.
///
/// Rick reported the same defect twice: the document opened in the right half,
/// but the conversation was still laid out at FULL width behind it, so the
/// bubbles it was supposed to keep readable were covered. The first fix was a
/// half-screen dialog, which cannot fix this by construction — an overlay does
/// not resize what is under it. These tests assert the thing he asked for:
/// the child's WIDTH SHRINKS to half when a document is open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_split_host.dart';

class _MockRepo extends Mock implements DocRepository {}

const double _foldWidth  = 840;   // unfolded Pixel Fold inner screen
const double _phoneWidth = 412;   // folded / ordinary phone

void main() {
  setUpAll( () => registerFallbackValue(
    const DocLink( kind: DocLinkKind.unknown, rawHref: '', label: '', apiPath: '', query: {} ) ) );

  late _MockRepo repo;

  setUp( () {
    repo = _MockRepo();
    when( () => repo.fetch( any() ) ).thenAnswer( ( _ ) async => const DocContent(
      kind      : DocContentKind.markdown,
      mediaType : 'text/markdown',
      text      : '# the document',
    ) );
  } );

  final link = classifyDocHref( '/app/docs?path=lupin-mobile/README.md' );

  Future<DocSplitHostState> pump( WidgetTester tester, double width ) async {
    tester.view.physicalSize     = Size( width, 900 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );

    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: DocSplitHost(
          repository : () => repo,
          child      : Container( key: const Key( 'the-conversation' ), color: Colors.blue ),
        ),
      ),
    ) );
    await tester.pump();
    return tester.state<DocSplitHostState>( find.byType( DocSplitHost ) );
  }

  Size sizeOfChild( WidgetTester tester ) =>
      tester.getSize( find.byKey( const Key( 'the-conversation' ) ) );

  testWidgets( 'unfolded: the conversation SHRINKS to half the width, side by side with the document',
      ( tester ) async {
    final host = await pump( tester, _foldWidth );
    final full = sizeOfChild( tester ).width;
    expect( full, _foldWidth, reason: 'setup: full width with no document open' );

    host.open( link );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.docSplitRow ) ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.docPanel ) ),    findsOneWidget );
    final shrunk = sizeOfChild( tester ).width;
    expect( shrunk, closeTo( full / 2, 1.0 ),
        reason: 'THE BUG: the bubbles used to keep their full width behind the document' );
    expect( sizeOfChild( tester ).height, 900,
        reason: 'side by side — full height each' );
  } );

  testWidgets( 'phone-shaped: the conversation shrinks to half the HEIGHT, stacked above the document',
      ( tester ) async {
    final host = await pump( tester, _phoneWidth );
    expect( sizeOfChild( tester ).height, 900 );

    host.open( link );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.docSplitColumn ) ), findsOneWidget );
    expect( sizeOfChild( tester ).height, closeTo( 900 / 2, 1.0 ) );
    expect( sizeOfChild( tester ).width,  _phoneWidth );
  } );

  testWidgets( 'closing gives the whole screen back', ( tester ) async {
    final host = await pump( tester, _foldWidth );
    host.open( link );
    await tester.pump();
    expect( sizeOfChild( tester ).width, closeTo( _foldWidth / 2, 1.0 ) );

    await tester.tap( find.byKey( const Key( TestKeys.docViewerCloseButton ) ) );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.docPanel ) ), findsNothing );
    expect( sizeOfChild( tester ).width, _foldWidth );
  } );

  testWidgets( 'a second link replaces the open document, still one half each', ( tester ) async {
    final host = await pump( tester, _foldWidth );
    host.open( link );
    await tester.pump();
    host.open( classifyDocHref( '/app/docs?path=lupin-mobile/history.md' ) );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.docPanel ) ), findsOneWidget,
        reason: 'one document at a time — no stack of panels' );
    expect( sizeOfChild( tester ).width, closeTo( _foldWidth / 2, 1.0 ) );
  } );

  testWidgets( 'a link that cannot be fetched never takes half the screen', ( tester ) async {
    final host = await pump( tester, _foldWidth );

    host.open( classifyDocHref( 'https://example.com/whatever' ) );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.docPanel ) ), findsNothing );
    expect( sizeOfChild( tester ).width, _foldWidth );
  } );

  testWidgets( 'maybeOf finds the host from inside the child, and is null with no host', ( tester ) async {
    late BuildContext inside;
    tester.view.physicalSize     = const Size( _foldWidth, 900 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );

    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: DocSplitHost(
          repository : () => repo,
          child      : Builder( builder: ( ctx ) { inside = ctx; return const SizedBox(); } ),
        ),
      ),
    ) );
    expect( DocSplitHost.maybeOf( inside ), isNotNull );

    late BuildContext hostless;
    await tester.pumpWidget( MaterialApp(
      home: Builder( builder: ( ctx ) { hostless = ctx; return const SizedBox(); } ),
    ) );
    expect( DocSplitHost.maybeOf( hostless ), isNull,
        reason: 'the legacy conversation screens keep their own behaviour' );
  } );
}
