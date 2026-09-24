import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/data/doc_upload.dart';

import '../_helpers/stub_dio.dart';

/// Row 61ecfb22 — ⬆ Upload, against lupin 627ef22c8's contract.
String _jwt( Map<String, dynamic> claims ) {
  String seg( Object o ) => base64Url.encode( utf8.encode( jsonEncode( o ) ) ).replaceAll( "=", "" );
  return "${seg( { "alg": "HS256" } )}.${seg( claims )}.sig";
}

const _file = PickedDocFile( name: "notes.md", bytes: [ 35, 32, 104, 105 ] );

void main() {
  group( "tokenHasAdminRole — offers Upload, never authorises it", () {
    test( "roles containing admin", () {
      expect( tokenHasAdminRole( _jwt( { "roles": [ "user", "admin" ] } ) ), isTrue );
    } );
    test( "a single role claim", () {
      expect( tokenHasAdminRole( _jwt( { "role": "admin" } ) ), isTrue );
    } );
    test( "an ordinary user, junk and no token are all false, never a throw", () {
      expect( tokenHasAdminRole( _jwt( { "roles": [ "user" ] } ) ), isFalse );
      expect( tokenHasAdminRole( "not.a.jwt" ), isFalse );
      expect( tokenHasAdminRole( "nodots" ), isFalse );
      expect( tokenHasAdminRole( null ), isFalse );
    } );
  } );

  group( "uploadDirFor — the `dir` field", () {
    test( "scope plus path, no trailing slash", () {
      expect( uploadDirFor( "lupin", "src/rnd/" ), "lupin/src/rnd" );
    } );
    test( "a scope root is the scope alone, io included", () {
      expect( uploadDirFor( "lupin", "" ), "lupin" );
      expect( uploadDirFor( "io", "" ),    "io" );
      expect( uploadDirFor( "io", "podcasts" ), "io/podcasts" );
    } );
  } );

  group( "DocRepository.upload — what goes on the wire", () {
    late StubAdapter adapter;
    late DocRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = DocRepository( makeDio( adapter ) );
    } );

    Map<String, String> fields( RequestOptions o ) =>
        { for ( final f in ( o.data as FormData ).fields ) f.key: f.value };

    test( "a 201 posts dir, on_conflict=refuse and the file under its own name", () async {
      adapter.handlers[ "POST /api/docs/upload" ] = ( _ ) => jsonBody(
        { "path": "lupin/src/rnd/notes.md", "name": "notes.md", "size": 4, "replaced": false,
          "view_url": "/app/docs?path=lupin/src/rnd/notes.md" },
        status: 201,
      );

      final stored = await repo.upload( dir: "lupin/src/rnd", file: _file );

      final sent = adapter.captured.single;
      expect( fields( sent ), { "dir": "lupin/src/rnd", "on_conflict": "refuse" } );
      final part = ( sent.data as FormData ).files.single;
      expect( part.key,             "file" );
      expect( part.value.filename,  "notes.md" );
      expect( stored.name,          "notes.md" );
      expect( stored.replaced,      isFalse );
    } );

    test( "replace and rename go out as their own on_conflict", () async {
      adapter.handlers[ "POST /api/docs/upload" ] = ( _ ) => jsonBody(
        { "path": "io/x.md", "name": "x.md", "size": 4, "replaced": true }, status: 201 );
      await repo.upload( dir: "io", file: _file, onConflict: DocUploadConflictMode.replace );
      await repo.upload( dir: "io", file: _file, onConflict: DocUploadConflictMode.rename );
      expect( adapter.captured.map( ( o ) => fields( o )[ "on_conflict" ] ), [ "replace", "rename" ] );
    } );

    test( "a 409 carries the server's suggested name", () async {
      adapter.handlers[ "POST /api/docs/upload" ] = ( _ ) => jsonBody( {
        "detail": { "error": "exists", "message": "A file named notes.md already exists in lupin/src/rnd",
                    "suggested_name": "notes-2.md" },
      }, status: 409 );

      await expectLater(
        repo.upload( dir: "lupin/src/rnd", file: _file ),
        throwsA( isA<DocUploadConflict>()
            .having( ( e ) => e.suggestedName, "suggestedName", "notes-2.md" )
            .having( ( e ) => e.message, "message", contains( "already exists" ) ) ),
      );
    } );

    test( "a read-only mount's 403 arrives in the server's words", () async {
      adapter.handlers[ "POST /api/docs/upload" ] = ( _ ) => jsonBody(
        { "detail": "This folder is not writable on this server: lupin-mobile/src" }, status: 403 );

      await expectLater(
        repo.upload( dir: "lupin-mobile/src", file: _file ),
        throwsA( isA<DocApiException>()
            .having( ( e ) => e.statusCode, "status", 403 )
            .having( ( e ) => e.message, "message", contains( "not writable" ) ) ),
      );
    } );
  } );
}
