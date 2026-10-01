import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Downloads artifacts produced by agentic jobs and hands them to the OS.
///
/// Fetches from `GET /api/io/file?path=...`; sharing and opening use the OS share sheet
/// and the default app for the file type.
class IoFileService {
  final Dio _dio;

  /// Creates a service that issues its requests through [_dio].
  const IoFileService( this._dio );

  // ─────────────────────────────────────────────
  // Fetch raw bytes
  // ─────────────────────────────────────────────

  /// Fetches the server file at [path] as raw bytes.
  ///
  /// Throws [IoFileException] when the request fails, carrying the HTTP status if any.
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

  /// Downloads [path] into the temporary directory as [suggestedName] and returns the file.
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

  /// Opens the OS share sheet for [file].
  Future<void> shareToExternalApp( File file ) async {
    await Share.shareXFiles( [ XFile( file.path ) ] );
  }

  // ─────────────────────────────────────────────
  // Open in external app (PPTX, PDF)
  // ─────────────────────────────────────────────

  /// Opens [file] in the default external app (for example a PPTX or PDF viewer).
  ///
  /// Throws [IoFileException] when no app opens it.
  Future<void> openExternalApp( File file ) async {
    final result = await OpenFile.open( file.path );
    if ( result.type != ResultType.done ) {
      throw IoFileException( 'openExternalApp failed: ${result.message}' );
    }
  }
}

/// Failure from [IoFileService], with the HTTP status when the cause was a response.
class IoFileException implements Exception {
  /// What failed, in words for logs.
  final String message;

  /// HTTP status of the failed response, or null when there was none.
  final int?   statusCode;

  /// Creates an exception with [message] and an optional [statusCode].
  const IoFileException( this.message, { this.statusCode } );

  @override
  String toString() => 'IoFileException($statusCode): $message';
}
