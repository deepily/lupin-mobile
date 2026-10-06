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
/// Entries at error and above start a flush at once; others wait for the buffer size
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
  int _dropped = 0;

  /// Most entries waiting in the buffer; the oldest drop first.
  ///
  /// A batch being written is held apart from the buffer, so with a write in flight
  /// memory holds up to twice this many entries.
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
    _enforceCap();

    if (entry.level >= LogLevel.error || _buffer.length >= _bufferSize) {
      _flushBuffer();
    }
  }

  /// Drops the oldest entries beyond [maxBufferedEntries] and counts them.
  void _enforceCap() {
    final excess = _buffer.length - maxBufferedEntries;
    if (excess <= 0) return;
    _buffer.removeRange( 0, excess );
    _dropped += excess;
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
        final written = await _writeBatch();
        if (written && _dropped > 0) {
          _buffer.add( _dropNote( _dropped ) );
          _dropped    = 0;
          _flushAgain = true;
        }
      } while (_flushAgain);
    } finally {
      _flushing = null;
    }
  }

  /// Writes the buffered entries; returns false when the write failed and the entries were kept.
  Future<bool> _writeBatch() async {
    if (_buffer.isEmpty) return false;

    final batch = List<LogEntry>.of(_buffer);
    _buffer.clear();

    try {
      final logData = '${batch.map(_encode).join('\n')}\n';

      // Write to current log file
      await _storage.appendToFile(fileName, logData);

      // Check file size and rotate if necessary
      await _rotateLogsIfNeeded();
      return true;
    } catch (e) {
      // Keep the batch for the next attempt, bounded so a dead disk cannot grow memory.
      _buffer.insertAll(0, batch);
      _enforceCap();
      // Not routed through Logger: this destination is what Logger writes to.
      if (kDebugMode) {
        print('Failed to write logs to file: $e');
      }
      return false;
    }
  }

  /// Encodes one entry; an entry that cannot be encoded becomes a stub line, so it never blocks the batch.
  String _encode( LogEntry entry ) {
    try {
      return jsonEncode( entry.toJson() );
    } catch (_) {
      return jsonEncode( {
        'timestamp': entry.timestamp.toIso8601String(),
        'level'    : entry.level.name,
        if (entry.tag != null) 'tag': entry.tag,
        'message'  : 'unencodable entry',
      } );
    }
  }

  LogEntry _dropNote( int count ) => LogEntry(
    timestamp: DateTime.now(),
    level    : LogLevel.warning,
    message  : 'dropped $count log entries while the file write was stalled or failing',
    tag      : 'Logger',
  );

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
  /// Every string that leaves the logger is masked by `redactSecrets`: the message,
  /// tag, error text, stack trace, and every field of the context, including nested
  /// metadata. Stack traces are masked too because a trace can quote a URL or argument.
  ///
  /// Ensures:
  ///   - never throws: a failure while building or delivering an entry is dropped
  ///   - metadata that cannot be read costs the entry its context, not the entry itself
  ///   - an error whose `toString` throws is recorded by its runtime type
  ///   - with no destination attached, warnings and above go to `debugPrint` so an early failure is not lost
  static void log(
    LogLevel level,
    String message, {
    String? tag,
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    try {
      final logger = instance;

      if (level < logger._minLevel) return;

      LogContext? maskedContext;
      try {
        maskedContext = _maskedContext( context ?? logger._globalContext );
      } catch (_) {
        maskedContext = null;   // unreadable metadata costs the context, not the entry
      }

      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: level,
        message: redactSecrets( message ),
        tag: tag == null ? null : redactSecrets( tag ),
        context: maskedContext,
        error: error == null ? null : _maskedText( error ),
        stackTrace: stackTrace == null ? null : StackTrace.fromString( _maskedText( stackTrace ) ),
      );

      if (logger._destinations.isEmpty) {
        if (level >= LogLevel.warning) debugPrint( entry.toFormattedString() );
        return;
      }

      for (final destination in logger._destinations) {
        try {
          destination.write(entry);
        } catch (e) {
          if (kDebugMode) debugPrint( '[Logger] a destination failed: ${e.runtimeType}' );
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint( '[Logger] dropped an entry: ${e.runtimeType}' );
    }
  }

  static String _maskedText( Object value ) {
    try {
      return redactSecrets( value.toString() );
    } catch (_) {
      return '<${value.runtimeType}: toString failed>';
    }
  }

  static LogContext? _maskedContext( LogContext? context ) {
    if (context == null) return null;
    return LogContext(
      userId    : context.userId    == null ? null : redactSecrets( context.userId! ),
      sessionId : context.sessionId == null ? null : redactSecrets( context.sessionId! ),
      requestId : context.requestId == null ? null : redactSecrets( context.requestId! ),
      feature   : context.feature   == null ? null : redactSecrets( context.feature! ),
      metadata  : context.metadata == null ? null : _maskedMap( context.metadata!, 0 ),
    );
  }

  static const int _maxMaskDepth = 6;

  static Map<String, dynamic> _maskedMap( Map<dynamic, dynamic> map, int depth ) {
    final out = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = _maskedText( entry.key );
      out[ key ] = _maskedValue( entry.key, entry.value, depth + 1 );
    }
    return out;
  }

  /// Masks [value], using [key] so a credential under a field name the redactor knows is caught.
  static dynamic _maskedValue( Object? key, Object? value, int depth ) {
    if (value == null || value is num || value is bool) return value;
    if (depth > _maxMaskDepth) return '<nested too deep>';
    if (value is Map) return _maskedMap( value, depth );
    if (value is Iterable) return [for (final item in value) _maskedValue( key, item, depth + 1 )];

    final text = _maskedText( value );
    if (key == null) return text;
    final prefix = '${_maskedText( key )}: ';
    final keyed  = _maskedText( '$prefix$text' );
    return keyed.startsWith( prefix ) ? keyed.substring( prefix.length ) : text;
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

  /// Logs [message] at warning level, with an optional [error] and [stackTrace].
  static void warning(
    String message, {
    String? tag,
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogLevel.warning, message, tag: tag, context: context, error: error, stackTrace: stackTrace);
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

  /// Flushes every destination at once, so a slow or hung one cannot hold up the others.
  ///
  /// A destination that throws does not stop the rest. The first failure is rethrown once all have finished.
  static Future<void> flush() async {
    final logger = instance;
    Object?     firstError;
    StackTrace? firstStack;
    await Future.wait( [
      for (final destination in List<LogDestination>.of( logger._destinations ))
        Future<void>.sync( destination.flush ).catchError( ( Object e, StackTrace st ) {
          if (firstError == null) {
            firstError = e;
            firstStack = st;
          }
        } ),
    ] );
    if (firstError != null) Error.throwWithStackTrace( firstError!, firstStack! );
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

  /// Logs [message] at warning level, with an optional [error] and [stackTrace].
  void warning(
    String message, {
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger.warning(message, tag: tag, context: context, error: error, stackTrace: stackTrace);
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