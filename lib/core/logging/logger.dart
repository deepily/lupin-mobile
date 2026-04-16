import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../storage/storage_manager.dart';

/// Log levels for filtering and categorizing log messages
enum LogLevel {
  verbose(0, 'VERBOSE', '🔍'),
  debug(1, 'DEBUG', '🐛'),
  info(2, 'INFO', 'ℹ️'),
  warning(3, 'WARNING', '⚠️'),
  error(4, 'ERROR', '❌'),
  critical(5, 'CRITICAL', '🚨');

  const LogLevel(this.value, this.name, this.emoji);

  final int value;
  final String name;
  final String emoji;

  bool operator >=(LogLevel other) => value >= other.value;
  bool operator <=(LogLevel other) => value <= other.value;
  bool operator >(LogLevel other) => value > other.value;
  bool operator <(LogLevel other) => value < other.value;
}

/// Context information for log entries
class LogContext {
  final String? userId;
  final String? sessionId;
  final String? requestId;
  final String? feature;
  final Map<String, dynamic>? metadata;

  const LogContext({
    this.userId,
    this.sessionId,
    this.requestId,
    this.feature,
    this.metadata,
  });

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
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? tag;
  final LogContext? context;
  final Object? error;
  final StackTrace? stackTrace;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
    this.context,
    this.error,
    this.stackTrace,
  });

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
  void write(LogEntry entry);
  Future<void> flush();
}

/// Console log destination for development
class ConsoleLogDestination implements LogDestination {
  @override
  void write(LogEntry entry) {
    if (kDebugMode) {
      print(entry.toFormattedString());
    }
  }

  @override
  Future<void> flush() async {
    // Console output is immediate
  }
}

/// File log destination for persistent logging
class FileLogDestination implements LogDestination {
  final String fileName;
  final int maxFileSize;
  final int maxFiles;
  final StorageManager _storage;
  final List<LogEntry> _buffer = [];
  final int _bufferSize;

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
    
    if (_buffer.length >= _bufferSize) {
      _flushBuffer();
    }
  }

  @override
  Future<void> flush() async {
    await _flushBuffer();
  }

  Future<void> _flushBuffer() async {
    if (_buffer.isEmpty) return;

    try {
      final logData = _buffer.map((entry) => jsonEncode(entry.toJson())).join('\n') + '\n';
      
      // Write to current log file
      await _storage.appendToFile(fileName, logData);
      
      // Check file size and rotate if necessary
      await _rotateLogsIfNeeded();
      
      _buffer.clear();
    } catch (e) {
      // Fallback to console if file writing fails
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
  final String endpoint;
  final String apiKey;
  final List<LogEntry> _buffer = [];
  final int _bufferSize;
  final Duration _flushInterval;

  RemoteLogDestination({
    required this.endpoint,
    required this.apiKey,
    int bufferSize = 50,
    Duration flushInterval = const Duration(seconds: 30),
  }) : _bufferSize = bufferSize,
       _flushInterval = flushInterval {
    
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
  static Logger get instance => _instance ?? (_instance = Logger._());

  Logger._();

  LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;
  final List<LogDestination> _destinations = [];
  LogContext? _globalContext;

  /// Initialize logger with destinations
  static Future<void> initialize({
    LogLevel minLevel = LogLevel.info,
    bool enableConsole = true,
    bool enableFile = true,
    bool enableRemote = false,
    String? remoteEndpoint,
    String? remoteApiKey,
  }) async {
    final logger = Logger.instance;
    logger._minLevel = minLevel;
    
    // Add console destination
    if (enableConsole) {
      logger._destinations.add(ConsoleLogDestination());
    }
    
    // Add file destination
    if (enableFile) {
      final storage = await StorageManager.getInstance();
      logger._destinations.add(FileLogDestination(storage));
    }
    
    // Add remote destination
    if (enableRemote && remoteEndpoint != null && remoteApiKey != null) {
      logger._destinations.add(RemoteLogDestination(
        endpoint: remoteEndpoint,
        apiKey: remoteApiKey,
      ));
    }
  }

  /// Set global context for all log entries
  static void setGlobalContext(LogContext context) {
    instance._globalContext = context;
  }

  /// Set minimum log level
  static void setLevel(LogLevel level) {
    instance._minLevel = level;
  }

  /// Log a message with specified level
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
      message: message,
      tag: tag,
      context: context ?? logger._globalContext,
      error: error,
      stackTrace: stackTrace,
    );

    for (final destination in logger._destinations) {
      destination.write(entry);
    }
  }

  /// Convenience methods for different log levels
  static void verbose(String message, {String? tag, LogContext? context}) {
    log(LogLevel.verbose, message, tag: tag, context: context);
  }

  static void debug(String message, {String? tag, LogContext? context}) {
    log(LogLevel.debug, message, tag: tag, context: context);
  }

  static void info(String message, {String? tag, LogContext? context}) {
    log(LogLevel.info, message, tag: tag, context: context);
  }

  static void warning(String message, {String? tag, LogContext? context}) {
    log(LogLevel.warning, message, tag: tag, context: context);
  }

  static void error(
    String message, {
    String? tag,
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(LogLevel.error, message, tag: tag, context: context, error: error, stackTrace: stackTrace);
  }

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
  final String tag;

  TaggedLogger(this.tag);

  void verbose(String message, {LogContext? context}) {
    Logger.verbose(message, tag: tag, context: context);
  }

  void debug(String message, {LogContext? context}) {
    Logger.debug(message, tag: tag, context: context);
  }

  void info(String message, {LogContext? context}) {
    Logger.info(message, tag: tag, context: context);
  }

  void warning(String message, {LogContext? context}) {
    Logger.warning(message, tag: tag, context: context);
  }

  void error(
    String message, {
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger.error(message, tag: tag, context: context, error: error, stackTrace: stackTrace);
  }

  void critical(
    String message, {
    LogContext? context,
    Object? error,
    StackTrace? stackTrace,
  }) {
    Logger.critical(message, tag: tag, context: context, error: error, stackTrace: stackTrace);
  }
}