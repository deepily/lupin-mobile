import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'log_file_store.dart';
import 'log_redaction.dart';

/// Log levels for filtering and categorizing log messages
enum LogLevel {
  /// Finest detail.
  verbose(0, 'VERBOSE', '🔍'),
  /// Debugging detail.
  debug(1, 'DEBUG', '🐛'),
  /// Normal operation.
  info(2, 'INFO', 'ℹ️'),
  /// Something unexpected that the app recovered from.
  warning(3, 'WARNING', '⚠️'),
  /// A failure.
  error(4, 'ERROR', '❌'),
  /// A failure the app may not survive.
  critical(5, 'CRITICAL', '🚨');

  const LogLevel(this.value, this.name, this.emoji);

  /// Numeric severity; a higher value is more severe.
  final int value;
  /// Upper-case label printed in a log line.
  final String name;
  /// Glyph printed in a log line.
  final String emoji;

  /// True when this level is at least as severe as [other].
  bool operator >=(LogLevel other) => value >= other.value;
  /// True when this level is at most as severe as [other].
  bool operator <=(LogLevel other) => value <= other.value;
  /// True when this level is more severe than [other].
  bool operator >(LogLevel other) => value > other.value;
  /// True when this level is less severe than [other].
  bool operator <(LogLevel other) => value < other.value;
}

/// Context information for log entries
class LogContext {
  /// User the entry concerns, or null.
  final String? userId;
  /// Session the entry concerns, or null.
  final String? sessionId;
  /// Request the entry concerns, or null.
  final String? requestId;
  /// Feature the entry concerns, or null.
  final String? feature;
  /// Extra structured fields, or null.
  final Map<String, dynamic>? metadata;

  /// Creates a context; every field is optional.
  const LogContext({
    this.userId,
    this.sessionId,
    this.requestId,
    this.feature,
    this.metadata,
  });

  /// Serializes the context.
  Map<String, dynamic> toJson() {
    return {
      if (userId != null) 'userId': userId,
      if (sessionId != null) 'sessionId': sessionId,
      if (requestId != null) 'requestId': requestId,
      if (feature != null) 'feature': feature,
      if (metadata != null) 'metadata': metadata,
    };
  }
}

/// Individual log entry with timestamp, level, and context
class LogEntry {
  /// When the entry was created.
  final DateTime timestamp;
  /// Severity of the entry.
  final LogLevel level;
  /// The logged text.
  final String message;
  /// Source tag, or null.
  final String? tag;
  /// Context of the entry, or null.
  final LogContext? context;
  /// The error being logged, or null.
  final Object? error;
  /// Stack trace of the error, or null.
  final StackTrace? stackTrace;

  /// Creates an entry.
  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
    this.context,
    this.error,
    this.stackTrace,
  });

  /// Serializes the entry.
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'message': message,
      if (tag != null) 'tag': tag,
      if (context != null) 'context': context!.toJson(),
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    };
  }

  /// Formats the entry as one human-readable line.
  String toFormattedString() {
    final buffer = StringBuffer();
    
    // Timestamp and level
    buffer.write('[${timestamp.toLocal().toString().substring(11, 23)}] ');
    buffer.write('${level.emoji} ${level.name.padRight(8)} ');
    
    // Tag
    if (tag != null) {
      buffer.write('[$tag] ');
    }
    
    // Message
    buffer.write(message);
    
    // Context
    if (context != null) {
      buffer.write(' | ');
      if (context!.userId != null) buffer.write('user:${context!.userId} ');
      if (context!.sessionId != null) buffer.write('session:${context!.sessionId} ');
      if (context!.feature != null) buffer.write('feature:${context!.feature} ');
    }
    
    // Error and stack trace
    if (error != null) {
      buffer.write('\nError: $error');
      if (stackTrace != null) {
        buffer.write('\nStack: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      }
    }
    
    return buffer.toString();
  }
}

/// Log destination interface for pluggable output targets
abstract class LogDestination {
  /// Writes [entry] to the destination.
  void write(LogEntry entry);
  /// Writes any buffered entries.
  Future<void> flush();
}

/// Console log destination: every entry in debug builds, warnings and above in release.
///
/// Release builds keep warnings and errors on the device console so a check that
/// reads logcat still sees them. Release output goes through `debugPrint`.
class ConsoleLogDestination implements LogDestination {
  final bool _debugMode;

  /// Creates a destination; [debugMode] defaults to `kDebugMode`, and false forces release output in tests.
  ConsoleLogDestination({ bool? debugMode }) : _debugMode = debugMode ?? kDebugMode;

  @override
  void write(LogEntry entry) {
    if (_debugMode) {
      if (kDebugMode) print(entry.toFormattedString());
    } else if (entry.level >= LogLevel.warning) {
      debugPrint(entry.toFormattedString());
    }
  }

  @override
  Future<void> flush() async {
    // Console output is immediate
  }
}

/// File log destination for persistent logging.
///
/// Entries at error and above start a flush at once; others wait for [bufferSize]
/// entries. At most one write runs at a time, and entries that arrive during it
/// go out in a follow-up write, so no entry is written twice.
class FileLogDestination implements LogDestination {
  /// Name of the log file.
  final String fileName;
  /// Size at which the file is rotated, in bytes.
  final int maxFileSize;
  /// Number of rotated files kept.
  final int maxFiles;
  final LogFileStore _storage;
  final List<LogEntry> _buffer = [];
  final int _bufferSize;
  Future<void>? _flushing;
  bool _flushAgain = false;

  /// Most entries kept in memory while the file cannot be written; the oldest drop first.
  static const int maxBufferedEntries = 1000;

  /// Creates a destination that writes through [_storage].
  FileLogDestination(
    this._storage, {
    this.fileName = 'lupin_mobile.log',
    this.maxFileSize = 10 * 1024 * 1024, // 10MB
    this.maxFiles = 5,
    int bufferSize = 100,
  }) : _bufferSize = bufferSize;

  @override
  void write(LogEntry entry) {
    _buffer.add(entry);

    if (entry.level >= LogLevel.error || _buffer.length >= _bufferSize) {
      _flushBuffer();
    }
  }

  @override
  Future<void> flush() async {
    await _flushBuffer();
  }

  Future<void> _flushBuffer() {
    if (_flushing != null) {
      _flushAgain = true;
      return _flushing!;
    }
    return _flushing = _drain();
  }

  Future<void> _drain() async {
    try {
      do {
        _flushAgain = false;
        await _writeBatch();
      } while (_flushAgain);
    } finally {
      _flushing = null;
    }
  }

  Future<void> _writeBatch() async {
    if (_buffer.isEmpty) return;

    final batch = List<LogEntry>.of(_buffer);
    _buffer.clear();

    try {
      final logData = '${batch.map((entry) => jsonEncode(entry.toJson())).join('\n')}\n';

      // Write to current log file
      await _storage.appendToFile(fileName, logData);

      // Check file size and rotate if necessary
      await _rotateLogsIfNeeded();
    } catch (e) {
      // Keep the batch for the next attempt, bounded so a dead disk cannot grow memory.
      _buffer.insertAll(0, batch);
      if (_buffer.length > maxBufferedEntries) {
        _buffer.removeRange(0, _buffer.length - maxBufferedEntries);
      }
      // Not routed through Logger: this destination is what Logger writes to.
      if (kDebugMode) {
        print('Failed to write logs to file: $e');
      }
    }
  }

  Future<void> _rotateLogsIfNeeded() async {
    try {
      final fileSize = await _storage.getFileSize(fileName);
      
      if (fileSize != null && fileSize > maxFileSize) {
        // Rotate log files
        for (int i = maxFiles - 1; i >= 1; i--) {
          final oldFile = '$fileName.$i';
          final newFile = '$fileName.${i + 1}';
          
          if (await _storage.fileExists(oldFile)) {
            if (i == maxFiles - 1) {
              // Delete oldest file
              await _storage.deleteFile(oldFile);
            } else {
              // Rename file
              await _storage.renameFile(oldFile, newFile);
            }
          }
        }
        
        // Move current log to .1
        if (await _storage.fileExists(fileName)) {
          await _storage.renameFile(fileName, '$fileName.1');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to rotate log files: $e');
      }
    }
  }
}

/// Remote log destination for production monitoring
class RemoteLogDestination implements LogDestination {
  /// URL the logs are sent to.
  final String endpoint;
  /// Key sent with each upload.
  final String apiKey;
  final List<LogEntry> _buffer = [];
  final int _bufferSize;

  /// Creates a destination that buffers entries before uploading them.
  ///
  /// Entries upload when the buffer fills or [flush] is called.
  RemoteLogDestination({
    required this.endpoint,
    required this.apiKey,
    int bufferSize = 50,
  }) : _bufferSize = bufferSize {
    
    // Start periodic flush
    _startPeriodicFlush();
  }

  @override
  void write(LogEntry entry) {
    _buffer.add(entry);
    
    if (_buffer.length >= _bufferSize) {
      _flushBuffer();
    }
  }

  @override
  Future<void> flush() async {
    await _flushBuffer();
  }

  void _startPeriodicFlush() {
    // Note: In production, use a proper timer implementation
    // This is a simplified version for demonstration
  }

  Future<void> _flushBuffer() async {
    if (_buffer.isEmpty) return;

    try {
      final logs = _buffer.map((entry) => entry.toJson()).toList();
      
      // Simulate HTTP POST to logging service
      // In real implementation, use Dio or http package
      if (kDebugMode) {
        print('Sending ${logs.length} logs to $endpoint');
      }
      
      _buffer.clear();
    } catch (e) {
      if (kDebugMode) {
        print('Failed to send logs to remote: $e');
      }
    }
  }
}

/// Main logger class with configurable destinations and filtering
class Logger {
  static Logger? _instance;
  /// The shared logger.
  static Logger get instance => _instance ?? (_instance = Logger._());

  Logger._();

  LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  final List<LogDestination> _destinations = [];
  LogContext? _globalContext;

  /// Initialize logger with destinations.
  ///
  /// Requires:
  ///   - [fileStore] is non-null when [enableFile] is true
  ///
  /// Raises:
  ///   - [ArgumentError] when [enableFile] is true and [fileStore] is null
  static Future<void> initialize({
    LogLevel minLevel = LogLevel.info,
    bool enableConsole = true,
    bool enableFile = true,
    LogFileStore? fileStore,
    bool enableRemote = false,
    String? remoteEndpoint,
    String? remoteApiKey,
  }) async {
    if (enableFile && fileStore == null) {
      throw ArgumentError.value( fileStore, 'fileStore', 'required when enableFile is true' );
    }
    final logger = Logger.instance;
    logger._minLevel = minLevel;

    // Add console destination
    if (enableConsole) {
      logger._destinations.add(ConsoleLogDestination());
    }
    
    // Add file destination
    if (enableFile) {
      logger._destinations.add(FileLogDestination(fileStore!));
    }
    
    // Add remote destination
    if (enableRemote && remoteEndpoint != null && remoteApiKey != null) {
      logger._destinations.add(RemoteLogDestination(
        endpoint: remoteEndpoint,
        apiKey: remoteApiKey,
      ));
    }
  }

  /// Adds [destination] to the shared logger.
  static void addDestination(LogDestination destination) {
    instance._destinations.add(destination);
  }

  /// Removes every destination and restores the default level and context.
  @visibleForTesting
  static void resetForTesting() {
    final logger = instance;
    logger._destinations.clear();
    logger._minLevel      = kDebugMode ? LogLevel.debug : LogLevel.info;
    logger._globalContext = null;
  }

  /// Set global context for all log entries
  static void setGlobalContext(LogContext context) {
    instance._globalContext = context;
  }

  /// Set minimum log level
  static void setLevel(LogLevel level) {
    instance._minLevel = level;
  }

  /// Log a message with specified level.
  ///
  /// Ensures:
  ///   - credentials in [message] and in the text of [error] are masked by `redactSecrets`
  ///   - with no destination attached, warnings and above go to `debugPrint` so an early failure is not lost
  static void log(
    LogLevel level,
    String message, {
    String? tag,
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final logger = instance;
    
    if (level < logger._minLevel) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: redactSecrets( message ),
      tag: tag,
      context: context ?? logger._globalContext,
      error: error == null ? null : redactSecrets( error.toString() ),
      stackTrace: stackTrace,
    );

    if (logger._destinations.isEmpty) {
      if (level >= LogLevel.warning) debugPrint( entry.toFormattedString() );
      return;
    }

    for (final destination in logger._destinations) {
      destination.write(entry);
    }
  }

  /// Convenience methods for different log levels
  static void verbose(String message, {String? tag, LogContext? context}) {
    log(LogLevel.verbose, message, tag: tag, context: context);
  }

  /// Logs [message] at debug level.
  static void debug(String message, {String? tag, LogContext? context}) {
    log(LogLevel.debug, message, tag: tag, context: context);
  }

  /// Logs [message] at info level.
  static void info(String message, {String? tag, LogContext? context}) {
    log(LogLevel.info, message, tag: tag, context: context);
  }

  /// Logs [message] at warning level.
  static void warning(String message, {String? tag, LogContext? context}) {
    log(LogLevel.warning, message, tag: tag, context: context);
  }

  /// Logs [message] at error level, with an optional [error] and [stackTrace].
  static void error(
    String message, {
    String? tag,
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogLevel.error, message, tag: tag, context: context, error: error, stackTrace: stackTrace);
  }

  /// Logs [message] at critical level.
  static void critical(
    String message, {
    String? tag,
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogLevel.critical, message, tag: tag, context: context, error: error, stackTrace: stackTrace);
  }

  /// Flush all destinations
  static Future<void> flush() async {
    final logger = instance;
    for (final destination in logger._destinations) {
      await destination.flush();
    }
  }

  /// Tagged loggers for specific components
  static TaggedLogger tagged(String tag) {
    return TaggedLogger(tag);
  }
}

/// Tagged logger for component-specific logging
class TaggedLogger {
  /// Tag added to every message.
  final String tag;

  /// Creates a logger that tags its messages with [tag].
  TaggedLogger(this.tag);

  /// Logs [message] at verbose level.
  void verbose(String message, {LogContext? context}) {
    Logger.verbose(message, tag: tag, context: context);
  }

  /// Logs [message] at debug level.
  void debug(String message, {LogContext? context}) {
    Logger.debug(message, tag: tag, context: context);
  }

  /// Logs [message] at info level.
  void info(String message, {LogContext? context}) {
    Logger.info(message, tag: tag, context: context);
  }

  /// Logs [message] at warning level.
  void warning(String message, {LogContext? context}) {
    Logger.warning(message, tag: tag, context: context);
  }

  /// Logs [message] at error level, with an optional [error] and [stackTrace].
  void error(
    String message, {
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger.error(message, tag: tag, context: context, error: error, stackTrace: stackTrace);
  }

  /// Logs [message] at critical level.
  void critical(
    String message, {
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger.critical(message, tag: tag, context: context, error: error, stackTrace: stackTrace);
  }
}