import 'dart:convert';

import 'package:dio/dio.dart';

import 'doc_link.dart';
import 'doc_models.dart';
import 'doc_upload.dart';

/// Fetches doc-viewer targets over the shared Dio.
///
/// The auth interceptor registered in `service_locator.dart` injects the Bearer token and
/// refreshes on 401, so nothing here touches credentials.
///
/// One URL answers with text, image bytes, or a JSON directory listing. Every response is
/// fetched as raw bytes and dispatched on the `content-type` header, not the file
/// extension, because a directory has no extension at all.
class DocRepository {
  final Dio _dio;

  /// Creates a repository over [_dio].
  const DocRepository( this._dio );

  /// Fetches the document a [DocLink] points at.
  ///
  /// Requires:
  ///     - link.isFetchable is true (kind is docs or io)
  ///
  /// Ensures:
  ///     - returns a DocContent whose kind reflects the server's content-type
  ///     - text is UTF-8 decoded for text/* responses; bytes are retained
  ///       undecoded for image/*
  ///     - a JSON body on a docs path is parsed as a directory listing
  ///
  /// Raises:
  ///     - ArgumentError if the link is not fetchable
  ///     - DocApiException on any transport or HTTP failure, carrying the
  ///       server's own `detail` message unedited when one was supplied
  Future<DocContent> fetch( DocLink link ) async {
    if ( !link.isFetchable ) {
      throw ArgumentError.value( link, "link", "not a fetchable doc link" );
    }

    try {
      final res = await _dio.get<List<int>>(
        link.apiPath,
        queryParameters: link.query,
        options        : Options(
          responseType: ResponseType.bytes,
          // Every status reaches our own handler so the server's `detail` text survives.
          validateStatus: ( _ ) => true,
        ),
      );

      final status = res.statusCode ?? 0;
      final bytes  = res.data ?? const <int>[];

      if ( status < 200 || status >= 300 ) {
        throw DocApiException( _detailFrom( bytes, status ), statusCode: status );
      }

      final mediaType = ( res.headers.value( "content-type" ) ?? "" ).trim();
      return _toContent( mediaType, bytes );
    } on DioException catch ( e ) {
      throw DocApiException(
        e.message ?? "Could not reach the document server.",
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Maps a media type plus its bytes onto a renderable DocContent.
  ///
  /// It is public so tests can cover the dispatch without a live Dio.
  static DocContent toContent( String mediaType, List<int> bytes ) =>
      _toContent( mediaType, bytes );

  static DocContent _toContent( String mediaType, List<int> bytes ) {
    final lower = mediaType.toLowerCase();

    if ( lower.startsWith( "image/" ) ) {
      return DocContent( kind: DocContentKind.image, mediaType: mediaType, bytes: bytes );
    }

    // PDF, audio, video and office files arrive as bytes; decoding them as text paints garbage.
    if ( _isBinary( lower ) ) {
      return DocContent( kind: DocContentKind.binary, mediaType: mediaType, bytes: bytes );
    }

    final text = _decode( bytes );

    // A JSON body here means a directory listing, not a .json document.
    // The file branch serves .json as `application/json` too, so shape decides.
    if ( lower.startsWith( "application/json" ) ) {
      final listing = _tryListing( text );
      if ( listing != null ) {
        return DocContent(
          kind      : DocContentKind.directory,
          mediaType : mediaType,
          listing   : listing,
        );
      }
      // A real .json document: show it as source, not as mangled markdown.
      return DocContent( kind: DocContentKind.source, mediaType: mediaType, text: text, bytes: bytes );
    }

    if ( lower.startsWith( "text/markdown" ) ) {
      return DocContent( kind: DocContentKind.markdown, mediaType: mediaType, text: text, bytes: bytes );
    }

    if ( lower.startsWith( "text/html" ) ) {
      return DocContent( kind: DocContentKind.html, mediaType: mediaType, text: text, bytes: bytes );
    }

    // Everything else is source-like text (.py, .yaml, .sh, .sql, .toml, .ini, .xml, .txt).
    // Markdown rendering would turn `# comment` into a heading, so it gets the source branch.
    return DocContent( kind: DocContentKind.source, mediaType: mediaType, text: text, bytes: bytes );
  }

  /// Media types the viewer cannot preview and must not decode as text.
  static bool _isBinary( String lower ) =>
      lower.startsWith( "audio/" ) ||
      lower.startsWith( "video/" ) ||
      lower.startsWith( "application/pdf" ) ||
      lower.startsWith( "application/octet-stream" ) ||
      lower.startsWith( "application/vnd." ) ||
      lower.startsWith( "application/zip" );

  /// Stores [file] in the folder [dir] (see `uploadDirFor`).
  ///
  /// Requires:
  ///   - [dir] is `<scope>/<rel-dir>`, `<scope>`, or `io[/<rel-dir>]`
  ///
  /// Ensures:
  ///   - 201 → the stored file, under the name the server actually used
  ///   - 409 → [DocUploadConflict] carrying the server's `suggested_name`
  ///   - anything else → [DocApiException] in the server's own words, so a
  ///     read-only mount's 403 says so rather than "failed"
  Future<DocUploadResult> upload( {
    required String         dir,
    required PickedDocFile  file,
    DocUploadConflictMode   onConflict = DocUploadConflictMode.refuse,
  } ) async {
    final form = FormData.fromMap( {
      "dir"         : dir,
      "on_conflict" : onConflict.name,
      "file"        : MultipartFile.fromBytes( file.bytes, filename: file.name ),
    } );
    try {
      final res = await _dio.post<dynamic>(
        "/api/docs/upload",
        data   : form,
        options: Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      final data   = res.data;
      if ( status == 201 || status == 200 ) {
        return DocUploadResult.fromJson( Map<String, dynamic>.from( data as Map ) );
      }
      final detail = data is Map ? data[ "detail" ] : null;
      if ( status == 409 ) {
        final d = detail is Map ? detail : const {};
        throw DocUploadConflict(
          ( d[ "message" ] ?? "A file with that name already exists." ).toString(),
          suggestedName: d[ "suggested_name" ]?.toString(),
        );
      }
      throw DocApiException(
        detail is String ? detail : "The upload failed with status $status.",
        statusCode: status,
      );
    } on DioException catch ( e ) {
      throw DocApiException(
        e.message ?? "Could not reach the document server.",
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// The browsable roots, from `GET /api/docs/scopes`.
  ///
  /// Ensures:
  ///   - one [DocScope] per registered scope, in the server's order
  ///   - does not include `io`; the Roots panel adds that root itself
  ///   - failures raise [DocApiException] in the server's own words
  Future<List<DocScope>> fetchScopes() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/api/docs/scopes",
        options: Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      final data   = res.data;
      if ( status < 200 || status >= 300 || data == null ) {
        final detail = data?[ "detail" ]?.toString();
        throw DocApiException(
          detail ?? "The document server returned status $status.",
          statusCode: status,
        );
      }
      final raw = data[ "scopes" ];
      if ( raw is! List ) return const [];
      return raw
          .whereType<Map>()
          .map( ( e ) => DocScope.fromJson( Map<String, dynamic>.from( e ) ) )
          .toList();
    } on DioException catch ( e ) {
      throw DocApiException(
        e.message ?? "Could not reach the document server.",
        statusCode: e.response?.statusCode,
      );
    }
  }

  /// Decodes UTF-8, tolerating malformed bytes: replacement characters beat a crash.
  static String _decode( List<int> bytes ) {
    try {
      return utf8.decode( bytes, allowMalformed: true );
    } catch ( _ ) {
      return "";
    }
  }

  /// Parses a directory listing, or null when the JSON is not one.
  static DocDirectoryListing? _tryListing( String text ) {
    try {
      final decoded = jsonDecode( text );
      // `kind == "directory"` decides when present, because a .json file is also
      // application/json and could carry an `entries` key. Bodies without `kind` keep
      // the older shape test.
      if ( decoded is Map<String, dynamic> &&
           decoded[ "entries" ] is List &&
           ( !decoded.containsKey( "kind" ) || decoded[ "kind" ] == "directory" ) ) {
        return DocDirectoryListing.fromJson( decoded );
      }
    } catch ( _ ) {
      // Not JSON, or not a listing: fall through to the caller's default.
    }
    return null;
  }

  /// Pulls the server's `detail` string out of an error body.
  ///
  /// The server's words are surfaced unedited. "Credential material" is a fact about the
  /// file, while "could not be read or decoded" is a fact about the disk or the mount.
  static String _detailFrom( List<int> bytes, int status ) {
    try {
      final decoded = jsonDecode( _decode( bytes ) );
      if ( decoded is Map && decoded[ "detail" ] != null ) {
        return decoded[ "detail" ].toString();
      }
    } catch ( _ ) {
      // A non-JSON error body falls through to the generic message.
    }
    return "The document server returned status $status.";
  }
}
