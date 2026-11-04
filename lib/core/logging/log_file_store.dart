/// The file operations the log file destination needs from local storage.
///
/// Lives apart from `StorageManager` so `logger.dart` imports no storage code and
/// storage can log through `Logger` without an import cycle.
abstract class LogFileStore {
  /// Appends [data] to [fileName], creating the file when missing.
  Future<void> appendToFile( String fileName, String data );

  /// Returns the size of [fileName] in bytes, or null when it cannot be read.
  Future<int?> getFileSize( String fileName );

  /// Returns whether [fileName] exists.
  Future<bool> fileExists( String fileName );

  /// Deletes [fileName].
  Future<void> deleteFile( String fileName );

  /// Renames [oldFileName] to [newFileName].
  Future<void> renameFile( String oldFileName, String newFileName );
}
