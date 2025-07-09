import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../base_repository.dart';
import '../../storage/storage_manager.dart';

/// Base implementation using SharedPreferences for web compatibility
abstract class SharedPreferencesRepository<T, ID> 
    implements BaseRepository<T, ID> {
  
  final String _keyPrefix;
  final String _counterKey;
  final String _allKeysKey;
  late final StorageManager _storage;
  
  SharedPreferencesRepository(this._keyPrefix) 
      : _counterKey = '${_keyPrefix}_counter',
        _allKeysKey = '${_keyPrefix}_all_keys' {
    _initStorage();
  }
  
  Future<void> _initStorage() async {
    _storage = await StorageManager.getInstance();
  }
  
  /// Convert entity to JSON
  Map<String, dynamic> toJson(T entity);
  
  /// Convert JSON to entity
  T fromJson(Map<String, dynamic> json);
  
  /// Get entity ID
  ID getId(T entity);
  
  /// Generate key for entity
  String getKey(ID id) => '${_keyPrefix}_$id';
  
  @override
  Future<T> create(T entity) async {
    await _ensureStorageReady();
    final id = getId(entity);
    final key = getKey(id);
    
    // Store entity
    final json = toJson(entity);
    await _storage.setJson(key, json);
    
    // Update all keys list
    await _addToAllKeys(id);
    
    // Update counter
    await _incrementCounter();
    
    return entity;
  }
  
  @override
  Future<T?> findById(ID id) async {
    await _ensureStorageReady();
    final key = getKey(id);
    final json = _storage.getJson(key);
    
    if (json == null) return null;
    
    try {
      return fromJson(json);
    } catch (e) {
      print('[Repository] Error parsing entity $id: $e');
      return null;
    }
  }
  
  @override
  Future<List<T>> findAll() async {
    await _ensureStorageReady();
    final allKeysJson = _storage.getJsonList(_allKeysKey) ?? [];
    final allKeys = allKeysJson.map((json) => json['id'] as String).toList();
    
    final List<T> results = [];
    
    for (final keyString in allKeys) {
      final id = _parseId(keyString);
      final entity = await findById(id);
      if (entity != null) {
        results.add(entity);
      }
    }
    
    return results;
  }
  
  @override
  Future<T> update(T entity) async {
    final id = getId(entity);
    final exists = await this.exists(id);
    
    if (!exists) {
      throw Exception('Entity with id $id does not exist');
    }
    
    await _ensureStorageReady();
    final key = getKey(id);
    final json = toJson(entity);
    await _storage.setJson(key, json);
    
    return entity;
  }
  
  @override
  Future<void> deleteById(ID id) async {
    await _ensureStorageReady();
    final key = getKey(id);
    
    await _storage.remove(key);
    await _removeFromAllKeys(id);
    await _decrementCounter();
  }
  
  @override
  Future<void> delete(T entity) async {
    final id = getId(entity);
    await deleteById(id);
  }
  
  @override
  Future<bool> exists(ID id) async {
    await _ensureStorageReady();
    final key = getKey(id);
    return _storage.containsKey(key);
  }
  
  @override
  Future<int> count() async {
    await _ensureStorageReady();
    return _storage.getInt(_counterKey) ?? 0;
  }
  
  @override
  Future<void> clear() async {
    await _ensureStorageReady();
    await _storage.removeKeysWithPrefix(_keyPrefix);
  }
  
  /// Helper methods
  Future<void> _addToAllKeys(ID id) async {
    final allKeysJson = _storage.getJsonList(_allKeysKey) ?? [];
    final idString = id.toString();
    
    // Check if ID already exists
    final exists = allKeysJson.any((json) => json['id'] == idString);
    if (!exists) {
      allKeysJson.add({'id': idString, 'added_at': DateTime.now().toIso8601String()});
      await _storage.setJsonList(_allKeysKey, allKeysJson);
    }
  }
  
  Future<void> _removeFromAllKeys(ID id) async {
    final allKeysJson = _storage.getJsonList(_allKeysKey) ?? [];
    final idString = id.toString();
    
    allKeysJson.removeWhere((json) => json['id'] == idString);
    await _storage.setJsonList(_allKeysKey, allKeysJson);
  }
  
  Future<void> _incrementCounter() async {
    final count = _storage.getInt(_counterKey) ?? 0;
    await _storage.setInt(_counterKey, count + 1);
  }
  
  Future<void> _decrementCounter() async {
    final count = _storage.getInt(_counterKey) ?? 0;
    await _storage.setInt(_counterKey, count > 0 ? count - 1 : 0);
  }
  
  /// Parse ID from string - override for complex ID types
  ID _parseId(String idString) {
    if (ID == String) {
      return idString as ID;
    }
    // Add more ID type parsing as needed
    throw UnimplementedError('ID type $ID parsing not implemented');
  }
  
  /// Ensure storage is ready for use
  Future<void> _ensureStorageReady() async {
    // StorageManager initialization is handled in getInstance()
    // This method can be used for any additional setup if needed
  }
  
  /// Helper methods for filtering
  Future<List<T>> findWhere(bool Function(T) predicate) async {
    final allEntities = await findAll();
    return allEntities.where(predicate).toList();
  }
  
  Future<T?> findFirstWhere(bool Function(T) predicate) async {
    final allEntities = await findAll();
    try {
      return allEntities.firstWhere(predicate);
    } catch (e) {
      return null;
    }
  }
  
  Future<List<T>> findAllSorted(int Function(T, T) compare) async {
    final allEntities = await findAll();
    allEntities.sort(compare);
    return allEntities;
  }
}