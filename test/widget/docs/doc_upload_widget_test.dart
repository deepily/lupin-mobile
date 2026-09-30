import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/data/doc_upload.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_upload_sheet.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';

/// Row 61ecfb22 — ⬆ Upload driven through the real viewer.
class _Repo implements DocRepository {
  final List<DocUploadConflictMode> modes = [];
  final List<String> dirs = [];
  int fetches = 0;

  /// Answers each upload in turn: a result, or an exception to throw.
  final List<Object> answers;

  _Repo( this.answers );

  @override
  Future<DocContent> fetch( DocLink link ) async {
    fetches++;
    return const DocContent(
      kind     : DocContentKind.directory,
      mediaType: "application/json",
      listing  : DocDirectoryListing( scope: "lupin", path: "src/rnd", entries: [] ),
    );
  }

  @override
  Future<DocUploadResult> upload( {
    required String dir,
    required PickedDocFile file,
    DocUploadConflictMode onConflict = DocUploadConflictMode.refuse,
  } ) async {
    dirs.add( dir );
    modes.add( onConflict );
    final a = answers.removeAt( 0 );
    if ( a is DocUploadResult ) return a;
    throw a;
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

const _picked = PickedDocFile( name: "notes.md", bytes: [ 1 ] );
const _stored = DocUploadResult( path: "lupin/src/rnd/notes.md", name: "notes.md", size: 1, replaced: false );
const _clash  = DocUploadConflict( "A file named notes.md already exists", suggestedName: "notes-2.md" );

Future<void> _pump( WidgetTester tester, _Repo repo, { bool admin = true, bool picker = true } ) async {
  await tester.pumpWidget( MaterialApp(
    home: DocViewerScreen(
      link      : docLinkFor( "lupin", "src/rnd" ),
      repository: repo,
      canUpload : () => admin,
      pickFile  : picker ? () async => _picked : null,
    ),
  ) );
  await tester.pumpAndSettle();
}

Finder _key( String k ) => find.byKey( Key( k ) );

void main() {
  testWidgets( "offered on a listing to an admin with a picker, and nowhere else", ( tester ) async {
    await _pump( tester, _Repo( [] ) );
    expect( _key( TestKeys.docViewerUploadButton ), findsOneWidget );

    await _pump( tester, _Repo( [] ), admin: false );
    expect( _key( TestKeys.docViewerUploadButton ), findsNothing );

    // No picker at all: the one-line retreat if the plugin has to come out.
    final installed = platformDocFilePicker;
    platformDocFilePicker = null;
    addTearDown( () => platformDocFilePicker = installed );
    await _pump( tester, _Repo( [] ), picker: false );
    expect( _key( TestKeys.docViewerUploadButton ), findsNothing );
  } );

  test( "the plugin picker is installed by default", () {
    expect( platformDocFilePicker, isNotNull );
  } );

  testWidgets( "a clean upload refuses clashes, says so, and reloads the listing", ( tester ) async {
    final repo = _Repo( [ _stored ] );
    await _pump( tester, repo );
    final before = repo.fetches;

    await tester.tap( _key( TestKeys.docViewerUploadButton ) );
    await tester.pumpAndSettle();

    expect( repo.dirs,  [ "lupin/src/rnd" ] );
    expect( repo.modes, [ DocUploadConflictMode.refuse ] );
    expect( find.text( "Uploaded notes.md" ), findsOneWidget );
    expect( repo.fetches, before + 1 );
  } );

  testWidgets( "a clash offers Rename to the server's name, then re-sends as rename", ( tester ) async {
    final repo = _Repo( [ _clash, _stored ] );
    await _pump( tester, repo );

    await tester.tap( _key( TestKeys.docViewerUploadButton ) );
    await tester.pumpAndSettle();
    expect( _key( TestKeys.docUploadConflictSheet ), findsOneWidget );
    expect( find.text( "Rename to notes-2.md" ), findsOneWidget );

    await tester.tap( _key( TestKeys.docUploadRename ) );
    await tester.pumpAndSettle();
    expect( repo.modes, [ DocUploadConflictMode.refuse, DocUploadConflictMode.rename ] );
  } );

  testWidgets( "Replace re-sends as replace", ( tester ) async {
    final repo = _Repo( [ _clash, _stored ] );
    await _pump( tester, repo );
    await tester.tap( _key( TestKeys.docViewerUploadButton ) );
    await tester.pumpAndSettle();
    await tester.tap( _key( TestKeys.docUploadReplace ) );
    await tester.pumpAndSettle();
    expect( repo.modes.last, DocUploadConflictMode.replace );
  } );

  testWidgets( "Cancel sends nothing more", ( tester ) async {
    final repo = _Repo( [ _clash ] );
    await _pump( tester, repo );
    await tester.tap( _key( TestKeys.docViewerUploadButton ) );
    await tester.pumpAndSettle();
    await tester.tap( _key( TestKeys.docUploadCancel ) );
    await tester.pumpAndSettle();
    expect( repo.modes, [ DocUploadConflictMode.refuse ] );
  } );

  testWidgets( "a 403 shows the server's own sentence", ( tester ) async {
    final repo = _Repo( [ const DocApiException( "This folder is not writable on this server: lupin/src/rnd", statusCode: 403 ) ] );
    await _pump( tester, repo );
    await tester.tap( _key( TestKeys.docViewerUploadButton ) );
    await tester.pumpAndSettle();
    expect( find.textContaining( "not writable" ), findsOneWidget );
  } );
}
