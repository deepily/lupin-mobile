import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

/// Storage manager for handling local data persistence
class StorageManager {
  static StorageManager? _instance;
  static final Completer<StorageManager> _completer = Completer<StorageManager>();
  
  SharedPreferences? _prefs;
  String? _documentsPath;
  
  StorageManager._();
  
  /// Get the singleton instance
  static Future<StorageManager> getInstance() async {
    if (_instance == null) {
      _instance = StorageManager._();
      await _instance!._initialize();
      _completer.complete(_instance);
    }
    return _completer.future;
  }
  
  /// Initialize the storage manager
  Future<void> _initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final documentsDir = await getApplicationDocumentsDirectory();
    _documentsPath = documentsDir.path;
  }
  
  /// Store a string value
  Future<bool> setString(String key, String value) async {
    return await _prefs!.setString(key, value);
  }
  
  /// Get a string value
  String? getString(String key) {
    return _prefs!.getString(key);
  }
  
  /// Store an integer value
  Future<bool> setInt(String key, int value) async {
    return await _prefs!.setInt(key, value);
  }
  
  /// Get an integer value
  int? getInt(String key) {
    return _prefs!.getInt(key);
  }
  
  /// Store a boolean value
  Future<bool> setBool(String key, bool value) async {
    return await _prefs!.setBool(key, value);
  }
  
  /// Get a boolean value
  bool? getBool(String key) {
    return _prefs!.getBool(key);
  }
  
  /// Store a double value
  Future<bool> setDouble(String key, double value) async {
    return await _prefs!.setDouble(key, value);
  }
  
  /// Get a double value
  double? getDouble(String key) {
    return _prefs!.getDouble(key);
  }
  
  /// Store a list of strings
  Future<bool> setStringList(String key, List<String> value) async {
    return await _prefs!.setStringList(key, value);
  }
  
  /// Get a list of strings
  List<String>? getStringList(String key) {
    return _prefs!.getStringList(key);
  }
  
  /// Store a JSON object
  Future<bool> setJson(String key, Map<String, dynamic> value) async {
    final jsonString = jsonEncode(value);
    return await setString(key, jsonString);
  }
  
  /// Get a JSON object
  Map<String, dynamic>? getJson(String key) {
    final jsonString = getString(key);
    if (jsonString == null) return null;
    
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      print('[StorageManager] Error parsing JSON for key $key: $e');
      return null;
    }
  }
  
  /// Store a list of JSON objects
  Future<bool> setJsonList(String key, List<Map<String, dynamic>> value) async {
    final jsonString = jsonEncode(value);
    return await setString(key, jsonString);
  }
  
  /// Get a list of JSON objects
  List<Map<String, dynamic>>? getJsonList(String key) {
    final jsonString = getString(key);
    if (jsonString == null) return null;
    
    try {
      final decoded = jsonDecode(jsonString) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (e) {
      print('[StorageManager] Error parsing JSON list for key $key: $e');
      return null;
    }
  }
  
  /// Check if a key exists
  bool containsKey(String key) {
    return _prefs!.containsKey(key);
  }
  
  /// Remove a key
  Future<bool> remove(String key) async {
    return await _prefs!.remove(key);
  }
  
  /// Clear all data
  Future<bool> clear() async {
    return await _prefs!.clear();
  }
  
  /// Get all keys
  Set<String> getKeys() {
    return _prefs!.getKeys();
  }
  
  /// Get all keys with a specific prefix
  Set<String> getKeysWithPrefix(String prefix) {
    return _prefs!.getKeys().where((key) => key.startsWith(prefix)).toSet();
  }
  
  /// Remove all keys with a specific prefix
  Future<void> removeKeysWithPrefix(String prefix) async {
    final keys = getKeysWithPrefix(prefix);
    for (final key in keys) {
      await remove(key);
    }
  }
  
  /// Get storage statistics
  StorageStats getStorageStats() {
    final keys = getKeys();
    final totalKeys = keys.length;
    
    // Calculate approximate size (this is a rough estimate)
    int totalSize = 0;
    final Map<String, int> keysByPrefix = {};
    
    for (final key in keys) {
      final value = _prefs!.get(key);
      if (value != null) {
        totalSize += key.length + value.toString().length;
        
        // Group by prefix
        final prefix = key.split('_').first;
        keysByPrefix[prefix] = (keysByPrefix[prefix] ?? 0) + 1;
      }
    }
    
    return StorageStats(
      totalKeys: totalKeys,
      approximateSize: totalSize,
      keysByPrefix: keysByPrefix,
    );
  }

  // File operations for logging and caching

  /// Append data to a file
  Future<void> appendToFile(String fileName, String data) async {
    try {
      final file = File('${_documentsPath}/$fileName');
      await file.writeAsString(data, mode: FileMode.append);
    } catch (e) {
      print('[StorageManager] Failed to append to file $fileName: $e');
      rethrow;
    }
  }

  /// Check if file exists
  Future<bool> fileExists(String fileName) async {
    try {
      final file = File('${_documentsPath}/$fileName');
      return await file.exists();
    } catch (e) {
      print('[StorageManager] Failed to check file existence for $fileName: $e');
      return false;
    }
  }

  /// Get file size in bytes
  Future<int?> getFileSize(String fileName) async {
    try {
      final file = File('${_documentsPath}/$fileName');
      if (await file.exists()) {
        return await file.length();
      }
      return null;
    } catch (e) {
      print('[StorageManager] Failed to get file size for $fileName: $e');
      return null;
    }
  }

  /// Rename a file
  Future<void> renameFile(String oldFileName, String newFileName) async {
    try {
      final oldFile = File('${_documentsPath}/$oldFileName');
      final newFile = File('${_documentsPath}/$newFileName');
      
      if (await oldFile.exists()) {
        await oldFile.rename(newFile.path);
      }
    } catch (e) {
      print('[StorageManager] Failed to rename file $oldFileName to $newFileName: $e');
      rethrow;
    }
  }

  /// Delete a file
  Future<void> deleteFile(String fileName) async {
    try {
      final file = File('${_documentsPath}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('[StorageManager] Failed to delete file $fileName: $e');
      rethrow;
    }
  }

  /// Read file contents
  Future<String?> readFile(String fileName) async {
    try {
      final file = File('${_documentsPath}/$fileName');
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (e) {
      print('[StorageManager] Failed to read file $fileName: $e');
      return null;
    }
  }

  /// Write file contents
  Future<void> writeFile(String fileName, String content) async {
    try {
      final file = File('${_documentsPath}/$fileName');
      await file.writeAsString(content);
    } catch (e) {
      print('[StorageManager] Failed to write file $fileName: $e');
      rethrow;
    }
  }
}

/// Storage statistics
class StorageStats {
  final int totalKeys;
  final int approximateSize;
  final Map<String, int> keysByPrefix;
  
  const StorageStats({
    required this.totalKeys,
    required this.approximateSize,
    required this.keysByPrefix,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'total_keys': totalKeys,
      'approximate_size': approximateSize,
      'keys_by_prefix': keysByPrefix,
    };
  }
}