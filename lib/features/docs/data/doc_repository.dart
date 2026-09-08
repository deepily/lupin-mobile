import 'dart:convert';

import 'package:dio/dio.dart';

import 'doc_link.dart';
import 'doc_models.dart';

/// Fetches doc-viewer targets over the shared Dio.
///
/// The auth interceptor registered in `service_locator.dart` injects the Bearer
/// token and refreshes on 401, so nothing here touches credentials.
///
/// The endpoint is polymorphic — the same URL answers with text, image bytes,
/// or a JSON directory listing — so every response is fetched as raw bytes and
/// dispatched on the `content-type` header rather than on the file extension.
/// Extension-based dispatch would be wrong for exactly the case that matters:
/// a directory has no extension at all.
class DocRepository {
  final Dio _dio;

  const DocRepository( this._dio );

  /// Fetch the document a [DocLink] points at.
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
          // Let every status through to our own handler so the server's
          // `detail` text survives instead of being flattened into a Dio
          // "status 400" string.
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

  /// Map a media type plus its bytes onto a renderable DocContent.
  ///
  /// Visible for testing — the dispatch is the interesting logic and deserves
  /// direct coverage without a live Dio.
  static DocContent toContent( String mediaType, List<int> bytes ) =>
      _toContent( mediaType, bytes );

  static DocContent _toContent( String mediaType, List<int> bytes ) {
    final lower = mediaType.toLowerCase();

    if ( lower.startsWith( "image/" ) ) {
      return DocContent( kind: DocContentKind.image, mediaType: mediaType, bytes: bytes );
    }

    final text = _decode( bytes );

    // A JSON body on this endpoint means a directory listing, not a .json
    // document — the file branch serves .json as `application/json` too, so
    // shape decides, not the header alone.
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
      return DocContent( kind: DocContentKind.source, mediaType: mediaType, text: text );
    }

    if ( lower.startsWith( "text/markdown" ) ) {
      return DocContent( kind: DocContentKind.markdown, mediaType: mediaType, text: text );
    }

    if ( lower.startsWith( "text/html" ) ) {
      return DocContent( kind: DocContentKind.html, mediaType: mediaType, text: text );
    }

    // Everything else the endpoint serves is source-ish text: .py, .yaml, .sh,
    // .sql, .toml, .ini, .xml, and plain .txt. Rendering these as markdown
    // would turn `# comment` into a heading, so they get the source branch.
    return DocContent( kind: DocContentKind.source, mediaType: mediaType, text: text );
  }

  /// Decode UTF-8, tolerating malformed bytes rather than throwing — a viewer
  /// that shows replacement characters is more useful than one that shows a
  /// crash.
  static String _decode( List<int> bytes ) {
    try {
      return utf8.decode( bytes, allowMalformed: true );
    } catch ( _ ) {
      return "";
    }
  }

  /// Parse a directory listing, or null when the JSON is not one.
  static DocDirectoryListing? _tryListing( String text ) {
    try {
      final decoded = jsonDecode( text );
      if ( decoded is Map<String, dynamic> && decoded[ "entries" ] is List ) {
        return DocDirectoryListing.fromJson( decoded );
      }
    } catch ( _ ) {
      // Not JSON, or not a listing — fall through to the caller's default.
    }
    return null;
  }

  /// Pull the server's `detail` string out of an error body.
  ///
  /// The doc endpoint's refusals draw a distinction worth preserving verbatim:
  /// "this file's CONTENT is credential material" is a fact about the file,
  /// while "it could not be read or decoded" is a fact about the disk or the
  /// bind-mount. Paraphrasing them sends the reader hunting for key material
  /// that was never there, so the server's own words are what we surface.
  static String _detailFrom( List<int> bytes, int status ) {
    try {
      final decoded = jsonDecode( _decode( bytes ) );
      if ( decoded is Map && decoded[ "detail" ] != null ) {
        return decoded[ "detail" ].toString();
      }
    } catch ( _ ) {
      // Non-JSON error body; fall through to the generic message.
    }
    return "The document server returned status $status.";
  }
}
