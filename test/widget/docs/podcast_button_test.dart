import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_podcast.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';

/// P1: the Podcast button in the doc viewer app bar.

class _Repo implements DocRepository {
  final List<String> checked = [];
  final List<String> started = [];

  /// What the check does: null passes, an exception is thrown.
  Object? checkFails;

  /// What the start answers, or throws when it is an exception.
  Object  startAnswer = const DocPodcastStarted( jobId: "pg-abc123" );

  @override
  Future<DocContent> fetch( DocLink link ) async => const DocContent(
        kind: DocContentKind.markdown, mediaType: "text/markdown", text: "# Explainer",
      );

  @override
  Future<DocPodcastFacts> checkPodcast( String scopePath ) async {
    checked.add( scopePath );
    if ( checkFails != null ) throw checkFails!;
    return const DocPodcastFacts( name: "plan.md", size: 10 );
  }

  @override
  Future<DocPodcastStarted> startPodcast( String scopePath ) async {
    started.add( scopePath );
    if ( startAnswer is Exception ) throw startAnswer;
    return startAnswer as DocPodcastStarted;
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

void main() {
  final link = classifyDocHref( "/app/docs?path=lupin-mobile/src/rnd/plan.md", label: "Open: plan.md" );

  Future<void> pump( WidgetTester tester, _Repo repo, { DocLink? at } ) async {
    await tester.pumpWidget( MaterialApp(
      home: DocViewerScreen( link: at ?? link, repository: repo ),
    ) );
    await tester.pumpAndSettle();
  }

  Future<void> tapPodcast( WidgetTester tester ) async {
    await tester.tap( find.byKey( const Key( TestKeys.docViewerPodcastButton ) ) );
    await tester.pumpAndSettle();
  }

  testWidgets( "the Podcast button shows on a document", ( tester ) async {
    await pump( tester, _Repo() );
    expect( find.byKey( const Key( TestKeys.docViewerPodcastButton ) ), findsOneWidget );
  } );

  testWidgets( "the button is absent on a directory listing", ( tester ) async {
    final repo = _Repo();
    await tester.pumpWidget( MaterialApp(
      home: DocViewerScreen(
        link      : link,
        repository: _ListingRepo(),
      ),
    ) );
    await tester.pumpAndSettle();
    expect( find.byKey( const Key( TestKeys.docViewerPodcastButton ) ), findsNothing );
    expect( repo.started, isEmpty );
  } );

  testWidgets( "a tap opens the in-app sheet naming the file and sends nothing", ( tester ) async {
    final repo = _Repo();
    await pump( tester, repo );
    await tapPodcast( tester );

    expect( find.byKey( const Key( TestKeys.podcastConfirmSheet ) ), findsOneWidget );
    expect( find.text( "Podcast plan.md?" ), findsOneWidget );
    expect( find.byType( AlertDialog ), findsNothing );
    expect( repo.checked, isEmpty );
    expect( repo.started, isEmpty );
  } );

  testWidgets( "Yes checks, then posts the document as <scope>/<path>", ( tester ) async {
    final repo = _Repo();
    await pump( tester, repo );
    await tapPodcast( tester );
    await tester.tap( find.byKey( const Key( TestKeys.podcastConfirmYes ) ) );
    await tester.pumpAndSettle();

    expect( repo.checked, [ "lupin-mobile/src/rnd/plan.md" ] );
    expect( repo.started, [ "lupin-mobile/src/rnd/plan.md" ] );
    expect( find.text( "Podcast queued: job pg-abc123" ), findsOneWidget );
  } );

  testWidgets( "No posts nothing", ( tester ) async {
    final repo = _Repo();
    await pump( tester, repo );
    await tapPodcast( tester );
    await tester.tap( find.byKey( const Key( TestKeys.podcastConfirmNo ) ) );
    await tester.pumpAndSettle();

    expect( repo.checked, isEmpty );
    expect( repo.started, isEmpty );
    expect( find.byKey( const Key( TestKeys.podcastConfirmSheet ) ), findsNothing );
  } );

  testWidgets( "a refused check shows the server's sentence and posts nothing", ( tester ) async {
    final repo = _Repo()..checkFails = const DocApiException( "That file looks like a credential.", statusCode: 400 );
    await pump( tester, repo );
    await tapPodcast( tester );
    await tester.tap( find.byKey( const Key( TestKeys.podcastConfirmYes ) ) );
    await tester.pumpAndSettle();

    expect( find.byKey( const Key( TestKeys.podcastError ) ), findsOneWidget );
    expect( find.text( "That file looks like a credential." ), findsOneWidget );
    expect( repo.started, isEmpty );
  } );

  testWidgets( "a refused start shows the server's sentence", ( tester ) async {
    final repo = _Repo()..startAnswer = const DocApiException( "The job could not be queued.", statusCode: 502 );
    await pump( tester, repo );
    await tapPodcast( tester );
    await tester.tap( find.byKey( const Key( TestKeys.podcastConfirmYes ) ) );
    await tester.pumpAndSettle();

    expect( find.text( "The job could not be queued." ), findsOneWidget );
  } );

  testWidgets( "an already-started file names the earlier job", ( tester ) async {
    final repo = _Repo()..startAnswer = const DocPodcastStarted( jobId: "pg-old", alreadyStarted: true );
    await pump( tester, repo );
    await tapPodcast( tester );
    await tester.tap( find.byKey( const Key( TestKeys.podcastConfirmYes ) ) );
    await tester.pumpAndSettle();

    expect( find.text( "Already started: job pg-old" ), findsOneWidget );
  } );

  group( "DocRepository podcast calls", () {
    Dio dioReturning( int status, Object? data ) {
      final dio = Dio();
      dio.httpClientAdapter = _Adapter( status, data );
      return dio;
    }

    test( "check parses name and size", () async {
      final facts = await DocRepository( dioReturning( 200, { "ok": true, "name": "a.md", "size": 5 } ) ).checkPodcast( "p/a.md" );
      expect( facts.name, "a.md" );
      expect( facts.size, 5 );
    } );

    test( "check refusal carries the server's message and status", () async {
      final repo = DocRepository( dioReturning( 400, { "detail": { "code": "credential", "message": "No." } } ) );
      await expectLater(
        repo.checkPodcast( "p/a.md" ),
        throwsA( isA<DocApiException>().having( ( e ) => e.message, "message", "No." ).having( ( e ) => e.statusCode, "status", 400 ) ),
      );
    } );

    test( "start returns the job id", () async {
      final started = await DocRepository( dioReturning( 200, { "job_id": "pg-1" } ) ).startPodcast( "p/a.md" );
      expect( started.jobId, "pg-1" );
      expect( started.alreadyStarted, isFalse );
    } );

    test( "start 409 spent returns the earlier job", () async {
      final repo = DocRepository( dioReturning( 409, { "detail": { "code": "spent", "message": "x", "job_id": "pg-0" } } ) );
      final started = await repo.startPodcast( "p/a.md" );
      expect( started.jobId, "pg-0" );
      expect( started.alreadyStarted, isTrue );
    } );

    test( "start refusal without a message names the status", () async {
      final repo = DocRepository( dioReturning( 403, { "detail": "nope" } ) );
      await expectLater( repo.startPodcast( "p/a.md" ), throwsA( isA<DocApiException>().having( ( e ) => e.message, "message", "Podcast failed (HTTP 403)" ) ) );
    } );

    test( "a transport failure raises with no status", () async {
      final dio = Dio();
      dio.httpClientAdapter = _Adapter.failing();
      await expectLater( DocRepository( dio ).checkPodcast( "p/a.md" ), throwsA( isA<DocApiException>().having( ( e ) => e.statusCode, "status", isNull ) ) );
      await expectLater( DocRepository( dio ).startPodcast( "p/a.md" ), throwsA( isA<DocApiException>() ) );
    } );
  } );
}

class _ListingRepo implements DocRepository {
  @override
  Future<DocContent> fetch( DocLink link ) async => const DocContent(
        kind: DocContentKind.directory, mediaType: "application/json",
        listing: DocDirectoryListing( scope: "lupin-mobile", path: "src", entries: [] ),
      );

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

class _Adapter implements HttpClientAdapter {
  final int     status;
  final Object? data;
  final bool    fail;

  _Adapter( this.status, this.data ) : fail = false;
  _Adapter.failing() : status = 0, data = null, fail = true;

  @override
  Future<ResponseBody> fetch( RequestOptions options, Stream<List<int>>? body, Future<void>? cancel ) async {
    if ( fail ) throw DioException( requestOptions: options, message: "offline" );
    return ResponseBody.fromString(
      _json( data ), status, headers: { Headers.contentTypeHeader: [ Headers.jsonContentType ] },
    );
  }

  static String _json( Object? v ) => v is Map ? _enc( v ) : "null";
  static String _enc( Map m ) => "{${m.entries.map( ( e ) => '"${e.key}":${_val( e.value )}' ).join( "," )}}";
  static String _val( Object? v ) => v is Map ? _enc( v ) : v is String ? '"$v"' : "$v";

  @override
  void close( { bool force = false } ) {}
}
