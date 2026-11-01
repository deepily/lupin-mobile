import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/podcasts/data/podcast_drive_repository.dart';
import 'package:lupin_mobile/services/auth/auth_interceptor.dart';
import 'package:lupin_mobile/services/auth/auth_repository.dart';
import 'package:lupin_mobile/services/auth/auth_token_provider.dart';
import '../../../_helpers/fixture_loader.dart';
import '../../_helpers/stub_dio.dart';

Map<String, dynamic> folder( String job, { String? created, String title = "", List<Map<String, dynamic>> files = const [] } ) => {
  "job_folder": job, "title": title, if ( created != null ) "created_ts": created, "files": files,
};

Map<String, dynamic> file( String id, { String mime = "audio/mpeg" } ) => {
  "name": "$id.mp3", "mime": mime, "size": 1234, "drive_file_id": id, "stream_url": "/api/podcast-drive/stream/$id",
};

void main() {
  PodcastDriveRepository repoFor( StubAdapter a ) => PodcastDriveRepository( makeDio( a ) );

  test( "lists folders newest first, undated last, with their files", () async {
    final a = StubAdapter( { "GET /api/podcast-drive/list": ( _ ) => jsonBody( [
      folder( "pg-old", created: "2026-10-01T10:00:00Z", files: [ file( "a" ) ] ),
      folder( "pg-none" ),
      folder( "pg-new", created: "2026-11-01T10:00:00Z", title: "Explainer", files: [ file( "b" ) ] ),
    ] ) } );

    final folders = await repoFor( a ).list();

    expect( folders.map( ( f ) => f.jobFolder ), [ "pg-new", "pg-old", "pg-none" ] );
    expect( folders.first.title, "Explainer" );
    expect( folders[ 1 ].title, "pg-old", reason: "a blank title falls back to the folder name" );
    expect( folders.first.files.single.streamUrl, "/api/podcast-drive/stream/b" );
    expect( folders.first.files.single.isAudio, isTrue );
  } );

  test( "a 403 says only the Drive owner's login may list it", () async {
    final a = StubAdapter( { "GET /api/podcast-drive/list": ( _ ) => jsonBody( { "detail": "forbidden" }, status: 403 ) } );

    await expectLater( repoFor( a ).list(), throwsA( isA<PodcastDriveException>()
        .having( ( e ) => e.statusCode, "status", 403 )
        .having( ( e ) => e.message, "message", contains( "owns the Drive link" ) ) ) );
  } );

  test( "another failure carries the server's detail", () async {
    final a = StubAdapter( { "GET /api/podcast-drive/list": ( _ ) => jsonBody( { "detail": "Drive token expired" }, status: 502 ) } );

    await expectLater( repoFor( a ).list(), throwsA( isA<PodcastDriveException>()
        .having( ( e ) => e.statusCode, "status", 502 )
        .having( ( e ) => e.message, "message", "Drive token expired" ) ) );
  } );

  test( "a reply that is not the expected list is a PodcastDriveException, not a crash", () async {
    final a = StubAdapter( { "GET /api/podcast-drive/list": ( _ ) => jsonBody( [ { "title": "no folder name" } ] ) } );

    await expectLater( repoFor( a ).list(), throwsA( isA<PodcastDriveException>() ) );
  } );

  group( "an expired login", () {
    tearDown( clearAccessToken );

    Dio authDio( StubAdapter a, { required String? refreshToken } ) {
      final dio = makeDio( a );
      dio.interceptors.add( AuthInterceptor(
        dio              : dio,
        repo             : AuthRepository( dio ),
        readRefreshToken : () async => refreshToken,
        onTokensRotated  : ( _ ) async {},
        onRefreshFailed  : () async {},
      ) );
      return dio;
    }

    test( "a 401 refreshes the token and the retry's list is returned", () async {
      setAccessToken( "stale" );
      var calls = 0;
      final a = StubAdapter( {
        "GET /api/podcast-drive/list": ( _ ) => ++calls == 1 ? jsonBody( { "detail": "expired" }, status: 401 ) : jsonBody( [ folder( "pg-1", files: [ file( "a" ) ] ) ] ),
        "POST /auth/refresh"         : ( _ ) => jsonBodyFromFixture( "auth/refresh_response.json" ),
      } );

      final folders = await PodcastDriveRepository( authDio( a, refreshToken: "old-ref" ) ).list();

      expect( folders.single.jobFolder, "pg-1" );
      expect( calls, 2 );
      expect( a.captured.last.headers[ "Authorization" ], "Bearer fixture_access_token" );
    } );

    test( "a 401 that the refresh cannot fix asks to sign in again", () async {
      setAccessToken( "stale" );
      final a = StubAdapter( { "GET /api/podcast-drive/list": ( _ ) => jsonBody( { "detail": "expired" }, status: 401 ) } );

      await expectLater( PodcastDriveRepository( authDio( a, refreshToken: null ) ).list(), throwsA( isA<PodcastDriveException>()
          .having( ( e ) => e.statusCode, "status", 401 )
          .having( ( e ) => e.message, "message", contains( "Sign in again" ) ) ) );
    } );
  } );

  test( "parses a real reply captured from the live server (2026-11-01): one audio file, the script is not audio", () async {
    final real = [ {
      "job_folder": "2026-11-01-192026-2026.10.31-google-drive-sign-in-explainer",
      "title"     : "2026.10.31 Google Drive Sign In Explainer",
      "created_ts": "2026-11-01T19:20:28.213Z",
      "files"     : [
        { "name": "2026.10.31-google-drive-sign-in-explainer.md", "mime": "text/markdown", "size": 5566,
          "drive_file_id": "1wxSCnha8otJh1Mar9C1v8FQXlEYQq--d", "stream_url": "/api/podcast-drive/stream/1wxSCnha8otJh1Mar9C1v8FQXlEYQq--d" },
        { "name": "2026.11.01-192023-the-name-tag-problem-what-a-google-driv.mp3", "mime": "audio/mpeg", "size": 13363245,
          "drive_file_id": "1cpP6Bl6V0D-8dVaDaWkcBWX93sALP97I", "stream_url": "/api/podcast-drive/stream/1cpP6Bl6V0D-8dVaDaWkcBWX93sALP97I" },
      ],
    } ];
    final a = StubAdapter( { "GET /api/podcast-drive/list": ( _ ) => jsonBody( real ) } );

    final f = ( await repoFor( a ).list() ).single;

    expect( f.created, DateTime.utc( 2026, 11, 1, 19, 20, 28, 213 ).toLocal() );
    expect( f.files.where( ( x ) => x.isAudio ).single.streamUrl, "/api/podcast-drive/stream/1cpP6Bl6V0D-8dVaDaWkcBWX93sALP97I" );
    expect( f.files.first.isAudio, isFalse );
  } );

  test( "a null size, as the server sends for a file Drive gives no size, reads as zero", () {
    final f = DrivePodcastFile.fromJson( { ...file( "z" ), "size": null } );
    expect( f.size, 0 );
  } );
}
