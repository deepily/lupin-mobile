import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' show ResponseBody;
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/artifacts/io_file_service.dart';
import '../../_helpers/stub_dio.dart';

void main() {
  late Directory tmp;

  setUp( () => tmp = Directory.systemTemp.createTempSync( "io_file_download_test" ) );
  tearDown( () => tmp.deleteSync( recursive: true ) );

  test( "downloadTo streams the server file into the destination", () async {
    final adapter = StubAdapter( {
      "GET /api/io/file": ( _ ) => ResponseBody.fromBytes( Uint8List.fromList( [ 1, 2, 3 ] ), 200 ),
    } );
    final dest = File( "${tmp.path}/a.mp3.part" );

    await IoFileService( makeDio( adapter ) ).downloadTo( "io/a.mp3", dest );

    expect( dest.readAsBytesSync(), [ 1, 2, 3 ] );
    expect( adapter.captured.single.queryParameters, { "path": "io/a.mp3" } );
  } );

  test( "downloadTo turns a failed response into an IoFileException with the status", () async {
    final adapter = StubAdapter( { "GET /api/io/file": ( _ ) => jsonBody( { "detail": "gone" }, status: 404 ) } );

    await expectLater(
      IoFileService( makeDio( adapter ) ).downloadTo( "io/a.mp3", File( "${tmp.path}/a.mp3.part" ) ),
      throwsA( isA<IoFileException>().having( ( e ) => e.statusCode, "statusCode", 404 ) ),
    );
  } );
}
