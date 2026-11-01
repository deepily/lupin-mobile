import 'package:dio/dio.dart';

/// One audio file inside a podcast's Drive folder.
class DrivePodcastFile {
  /// The file name in Drive.
  final String name;

  /// The file's media type, for example `audio/mpeg`.
  final String mime;

  /// The size in bytes; zero when the server did not say.
  final int size;

  /// The Drive file id.
  final String driveFileId;

  /// The server path that streams the file; the player downloads it from here.
  final String streamUrl;

  /// Creates one file.
  const DrivePodcastFile( {
    required this.name,
    required this.mime,
    required this.size,
    required this.driveFileId,
    required this.streamUrl,
  } );

  /// True when the file is audio the player can play.
  bool get isAudio => mime.startsWith( "audio/" );

  /// Reads one file from the list endpoint's JSON.
  ///
  /// Requires:
  ///   - [json] holds `name`, `drive_file_id` and `stream_url` as strings
  ///
  /// Ensures:
  ///   - a missing `mime` reads as empty and a missing `size` as zero
  ///
  /// Raises:
  ///   - FormatException when a required field is missing or not a string
  factory DrivePodcastFile.fromJson( Map<String, dynamic> json ) {
    return DrivePodcastFile(
      name        : _requireString( json, "name" ),
      mime        : json[ "mime" ] is String ? json[ "mime" ] as String : "",
      size        : json[ "size" ] is num ? ( json[ "size" ] as num ).toInt() : 0,
      driveFileId : _requireString( json, "drive_file_id" ),
      streamUrl   : _requireString( json, "stream_url" ),
    );
  }
}

/// One podcast job's folder under "Lupin AF Mobile/Podcasts" in Drive.
class DrivePodcastFolder {
  /// The folder name, one per job.
  final String jobFolder;

  /// What the list shows as the podcast's title.
  final String title;

  /// When the folder was made; null when the server sent no readable time.
  final DateTime? created;

  /// The files in the folder, in the server's order.
  final List<DrivePodcastFile> files;

  /// Creates one folder.
  const DrivePodcastFolder( {
    required this.jobFolder,
    required this.title,
    required this.created,
    required this.files,
  } );

  /// Reads one folder from the list endpoint's JSON.
  ///
  /// Requires:
  ///   - [json] holds `job_folder` as a string and `files` as a list
  ///
  /// Ensures:
  ///   - a blank or missing `title` falls back to the folder name
  ///   - an unreadable `created_ts` reads as null
  ///
  /// Raises:
  ///   - FormatException when a required field is missing or the wrong type
  factory DrivePodcastFolder.fromJson( Map<String, dynamic> json ) {
    final folder = _requireString( json, "job_folder" );
    final title  = json[ "title" ] is String ? ( json[ "title" ] as String ).trim() : "";
    final files  = json[ "files" ];
    if ( files is! List ) throw const FormatException( "files is not a list" );
    return DrivePodcastFolder(
      jobFolder : folder,
      title     : title.isEmpty ? folder : title,
      created   : json[ "created_ts" ] is String ? DateTime.tryParse( json[ "created_ts" ] as String )?.toLocal() : null,
      files     : files.map( ( f ) => DrivePodcastFile.fromJson( Map<String, dynamic>.from( f as Map ) ) ).toList(),
    );
  }
}

/// A failed Drive listing, in words the screen can show.
class PodcastDriveException implements Exception {
  /// What went wrong, ready to show.
  final String message;

  /// The HTTP status, or null when the server was not reached.
  final int? statusCode;

  /// Creates the failure.
  const PodcastDriveException( this.message, { this.statusCode } );

  @override
  String toString() => "PodcastDriveException($statusCode): $message";
}

/// Lists the podcasts kept in Google Drive, through the Lupin server.
///
/// The server holds the Drive sign-in and reads the folder live on each call, so the
/// phone never signs in to Google. The shared Dio's auth interceptor adds the Bearer token.
class PodcastDriveRepository {
  /// The list endpoint.
  static const listPath = "/api/podcast-drive/list";

  final Dio _dio;

  /// Creates the repository over [_dio].
  const PodcastDriveRepository( this._dio );

  /// Every podcast folder in Drive, newest first.
  ///
  /// It calls `GET /api/podcast-drive/list`.
  ///
  /// Ensures:
  ///   - folders are sorted newest first; folders with no time go last
  ///
  /// Raises:
  ///   - a 401 goes through the auth interceptor's token refresh and retry first
  ///   - PodcastDriveException on a 401 that survives the refresh, asking to sign in again
  ///   - PodcastDriveException on a 403, saying only the Drive owner's login may list it
  ///   - PodcastDriveException on any other failure, carrying the server's `detail` when it sent one
  ///   - PodcastDriveException when the reply is not the expected list
  Future<List<DrivePodcastFolder>> list() async {
    final Response<dynamic> res;
    try {
      // A 401 stays an error so the auth interceptor refreshes the token and retries; every other
      // status reaches the checks below, so the server's own `detail` text survives.
      res = await _dio.get<dynamic>( listPath, options: Options( validateStatus: ( s ) => s != null && s != 401 ) );
    } on DioException catch ( e ) {
      final status = e.response?.statusCode;
      if ( status == 401 ) throw const PodcastDriveException( "Your login has expired. Sign in again to see the Drive podcasts.", statusCode: 401 );
      throw PodcastDriveException( "Could not reach the server: ${e.message ?? "no connection"}", statusCode: status );
    }
    final status = res.statusCode ?? 0;
    final data   = res.data;
    if ( status == 403 ) {
      throw const PodcastDriveException( "Only the login that owns the Drive link can see the Drive podcasts.", statusCode: 403 );
    }
    if ( status < 200 || status >= 300 ) {
      final detail = data is Map && data[ "detail" ] is String ? data[ "detail" ] as String : "The server answered $status.";
      throw PodcastDriveException( detail, statusCode: status );
    }
    if ( data is! List ) throw PodcastDriveException( "The server sent an unexpected reply.", statusCode: status );
    final List<DrivePodcastFolder> folders;
    try {
      folders = data.map( ( f ) => DrivePodcastFolder.fromJson( Map<String, dynamic>.from( f as Map ) ) ).toList();
    } on Object catch ( e ) {
      throw PodcastDriveException( "The server sent an unexpected reply: $e", statusCode: status );
    }
    folders.sort( ( a, b ) {
      if ( a.created == null ) return b.created == null ? 0 : 1;
      if ( b.created == null ) return -1;
      return b.created!.compareTo( a.created! );
    } );
    return folders;
  }
}

String _requireString( Map<String, dynamic> json, String key ) {
  final v = json[ key ];
  if ( v is! String || v.isEmpty ) throw FormatException( "$key is missing" );
  return v;
}
