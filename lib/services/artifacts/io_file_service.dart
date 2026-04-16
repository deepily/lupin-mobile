import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Service for downloading and sharing artifacts produced by agentic jobs.
/// Fetches from GET /api/io/file?path=... and delegates to OS share/open.
class IoFileService {
  final Dio _dio;
  const IoFileService( this._dio );

  // ─────────────────────────────────────────────
  // Fetch raw bytes
  // ─────────────────────────────────────────────

  Future<Uint8List> fetchBinary( String path ) async {
    try {
      final res = await _dio.get<List<int>>(
        '/api/io/file',
        queryParameters : { 'path': path },
        options         : Options( responseType: ResponseType.bytes ),
      );
      return Uint8List.fromList( res.data! );
    } on DioException catch ( e ) {
      throw IoFileException(
        'fetchBinary($path) failed',
        statusCode: e.response?.statusCode,
      );
    }
  }

  // ─────────────────────────────────────────────
  // Download to cache dir
  // ─────────────────────────────────────────────

  Future<File> downloadToCache( String path, String suggestedName ) async {
    final bytes   = await fetchBinary( path );
    final cacheDir = await getTemporaryDirectory();
    final file    = File( '${cacheDir.path}/$suggestedName' );
    await file.writeAsBytes( bytes );
    return file;
  }

  // ─────────────────────────────────────────────
  // Share via OS share sheet
  // ─────────────────────────────────────────────

  Future<void> shareToExternalApp( File file ) async {
    await Share.shareXFiles( [ XFile( file.path ) ] );
  }

  // ─────────────────────────────────────────────
  // Open in external app (PPTX, PDF)
  // ─────────────────────────────────────────────

  Future<void> openExternalApp( File file ) async {
    final result = await OpenFile.open( file.path );
    if ( result.type != ResultType.done ) {
      throw IoFileException( 'openExternalApp failed: ${result.message}' );
    }
  }
}

class IoFileException implements Exception {
  final String message;
  final int?   statusCode;

  const IoFileException( this.message, { this.statusCode } );

  @override
  String toString() => 'IoFileException($statusCode): $message';
}
