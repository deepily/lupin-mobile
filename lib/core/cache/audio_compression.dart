import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

/// Audio compression utilities for cache optimization
class AudioCompression {
  // Compression algorithms
  static const String _pcmCompression = 'pcm_lz4';
  static const String _wavCompression = 'wav_deflate';
  static const String _mp3Compression = 'mp3_vbr';
  
  // Compression settings
  final Map<String, CompressionSettings> _settings = {
    'pcm': CompressionSettings(
      algorithm: _pcmCompression,
      quality: 0.8,
      enableVBR: true,
      targetBitrate: 128,
    ),
    'wav': CompressionSettings(
      algorithm: _wavCompression,
      quality: 0.9,
      enableVBR: false,
      targetBitrate: 256,
    ),
    'mp3': CompressionSettings(
      algorithm: _mp3Compression,
      quality: 0.85,
      enableVBR: true,
      targetBitrate: 128,
    ),
  };
  
  // Compression cache
  final Map<String, Uint8List> _compressionCache = {};
  final Map<String, CompressionMetadata> _metadataCache = {};
  
  // Statistics
  int _totalCompressions = 0;
  int _totalDecompressions = 0;
  int _bytesCompressed = 0;
  int _bytesDecompressed = 0;
  int _bytesSaved = 0;
  
  /// Compress audio data
  Future<Uint8List> compress(
    Uint8List data, {
    required String format,
    double? quality,
    int? targetBitrate,
  }) async {
    if (data.isEmpty) return data;
    
    final startTime = DateTime.now();
    
    // Generate cache key
    final cacheKey = _generateCacheKey(data, format, quality, targetBitrate);
    
    // Check cache first
    if (_compressionCache.containsKey(cacheKey)) {
      return _compressionCache[cacheKey]!;
    }
    
    // Get compression settings
    final settings = _getCompressionSettings(format, quality, targetBitrate);
    
    // Compress based on format
    Uint8List compressed;
    CompressionMetadata metadata;
    
    switch (format.toLowerCase()) {
      case 'pcm':
        final result = await _compressPCM(data, settings);
        compressed = result.data;
        metadata = result.metadata;
        break;
      case 'wav':
        final result = await _compressWAV(data, settings);
        compressed = result.data;
        metadata = result.metadata;
        break;
      case 'mp3':
        final result = await _compressMP3(data, settings);
        compressed = result.data;
        metadata = result.metadata;
        break;
      default:
        // Fallback to generic compression
        final result = await _compressGeneric(data, settings);
        compressed = result.data;
        metadata = result.metadata;
    }
    
    // Cache the result
    _compressionCache[cacheKey] = compressed;
    _metadataCache[cacheKey] = metadata;
    
    // Limit cache size
    if (_compressionCache.length > 100) {
      _cleanupCompressionCache();
    }
    
    // Update statistics
    final duration = DateTime.now().difference(startTime);
    _updateCompressionStats(
      originalSize: data.length,
      compressedSize: compressed.length,
      duration: duration,
    );
    
    return compressed;
  }
  
  /// Decompress audio data
  Future<Uint8List> decompress(
    Uint8List data, {
    required String format,
    CompressionMetadata? metadata,
  }) async {
    if (data.isEmpty) return data;
    
    final startTime = DateTime.now();
    
    // Try to find metadata in cache
    CompressionMetadata? meta = metadata;
    if (meta == null) {
      // Look for metadata in cache
      final cacheKey = _findMetadataKey(data);
      if (cacheKey != null) {
        meta = _metadataCache[cacheKey];
      }
    }
    
    // Decompress based on format
    Uint8List decompressed;
    
    switch (format.toLowerCase()) {
      case 'pcm':
        decompressed = await _decompressPCM(data, meta);
        break;
      case 'wav':
        decompressed = await _decompressWAV(data, meta);
        break;
      case 'mp3':
        decompressed = await _decompressMP3(data, meta);
        break;
      default:
        // Fallback to generic decompression
        decompressed = await _decompressGeneric(data, meta);
    }
    
    // Update statistics
    final duration = DateTime.now().difference(startTime);
    _updateDecompressionStats(
      compressedSize: data.length,
      decompressedSize: decompressed.length,
      duration: duration,
    );
    
    return decompressed;
  }
  
  /// Get compression ratio for data
  double getCompressionRatio(Uint8List originalData, Uint8List compressedData) {
    if (originalData.isEmpty) return 1.0;
    return compressedData.length / originalData.length;
  }
  
  /// Get optimal compression settings for audio type
  CompressionSettings getOptimalSettings({
    required String format,
    required int sampleRate,
    required int bitDepth,
    required Duration duration,
  }) {
    final baseSettings = _settings[format.toLowerCase()] ?? _settings['pcm']!;
    
    // Adjust settings based on audio characteristics
    double quality = baseSettings.quality;
    int targetBitrate = baseSettings.targetBitrate;
    
    // Higher quality for short audio clips
    if (duration.inSeconds < 5) {
      quality = math.min(1.0, quality + 0.1);
    }
    
    // Adjust bitrate based on sample rate
    if (sampleRate > 44100) {
      targetBitrate = (targetBitrate * 1.5).round();
    } else if (sampleRate < 22050) {
      targetBitrate = (targetBitrate * 0.75).round();
    }
    
    return baseSettings.copyWith(
      quality: quality,
      targetBitrate: targetBitrate,
    );
  }
  
  /// Estimate compressed size
  int estimateCompressedSize(
    int originalSize,
    String format, {
    double? quality,
  }) {
    final settings = _getCompressionSettings(format, quality, null);
    
    // Rough estimation based on typical compression ratios
    double ratio;
    switch (format.toLowerCase()) {
      case 'pcm':
        ratio = 0.6; // PCM compresses well with lossless algorithms
        break;
      case 'wav':
        ratio = 0.7; // WAV has some redundancy
        break;
      case 'mp3':
        ratio = 0.1; // MP3 is already compressed
        break;
      default:
        ratio = 0.5;
    }
    
    // Adjust based on quality
    ratio *= settings.quality;
    
    return (originalSize * ratio).round();
  }
  
  /// Get compression statistics
  CompressionStatistics getStatistics() {
    final compressionRatio = _bytesCompressed > 0 
        ? (_bytesCompressed - _bytesSaved) / _bytesCompressed
        : 1.0;
    
    return CompressionStatistics(
      totalCompressions: _totalCompressions,
      totalDecompressions: _totalDecompressions,
      totalBytesCompressed: _bytesCompressed,
      totalBytesDecompressed: _bytesDecompressed,
      totalBytesSaved: _bytesSaved,
      averageCompressionRatio: compressionRatio,
      cacheSize: _compressionCache.length,
    );
  }
  
  /// Clear compression cache
  void clearCache() {
    _compressionCache.clear();
    _metadataCache.clear();
  }
  
  /// Reset statistics
  void resetStatistics() {
    _totalCompressions = 0;
    _totalDecompressions = 0;
    _bytesCompressed = 0;
    _bytesDecompressed = 0;
    _bytesSaved = 0;
  }
  
  // Private methods
  
  CompressionSettings _getCompressionSettings(
    String format,
    double? quality,
    int? targetBitrate,
  ) {
    final baseSettings = _settings[format.toLowerCase()] ?? _settings['pcm']!;
    
    return baseSettings.copyWith(
      quality: quality,
      targetBitrate: targetBitrate,
    );
  }
  
  String _generateCacheKey(
    Uint8List data,
    String format,
    double? quality,
    int? targetBitrate,
  ) {
    final hash = data.length.hashCode ^ 
                 format.hashCode ^ 
                 (quality?.hashCode ?? 0) ^ 
                 (targetBitrate?.hashCode ?? 0);
    return hash.toString();
  }
  
  String? _findMetadataKey(Uint8List data) {
    // Simple implementation - in practice would use better key matching
    for (final entry in _metadataCache.entries) {
      if (entry.value.compressedSize == data.length) {
        return entry.key;
      }
    }
    return null;
  }
  
  void _cleanupCompressionCache() {
    // Remove oldest entries if cache is too large
    if (_compressionCache.length <= 50) return;
    
    final keys = _compressionCache.keys.toList();
    for (int i = 0; i < keys.length - 50; i++) {
      _compressionCache.remove(keys[i]);
      _metadataCache.remove(keys[i]);
    }
  }
  
  Future<CompressionResult> _compressPCM(
    Uint8List data,
    CompressionSettings settings,
  ) async {
    // Simulate PCM compression using a simple algorithm
    final compressed = await _lz4Compress(data, settings.quality);
    
    final metadata = CompressionMetadata(
      originalSize: data.length,
      compressedSize: compressed.length,
      algorithm: settings.algorithm,
      quality: settings.quality,
      format: 'pcm',
      compressionRatio: compressed.length / data.length,
      timestamp: DateTime.now(),
    );
    
    return CompressionResult(data: compressed, metadata: metadata);
  }
  
  Future<CompressionResult> _compressWAV(
    Uint8List data,
    CompressionSettings settings,
  ) async {
    // Simulate WAV compression using deflate
    final compressed = await _deflateCompress(data, settings.quality);
    
    final metadata = CompressionMetadata(
      originalSize: data.length,
      compressedSize: compressed.length,
      algorithm: settings.algorithm,
      quality: settings.quality,
      format: 'wav',
      compressionRatio: compressed.length / data.length,
      timestamp: DateTime.now(),
    );
    
    return CompressionResult(data: compressed, metadata: metadata);
  }
  
  Future<CompressionResult> _compressMP3(
    Uint8List data,
    CompressionSettings settings,
  ) async {
    // MP3 is already compressed, so we just return the data
    // In a real implementation, this might re-encode with different settings
    final compressed = data;
    
    final metadata = CompressionMetadata(
      originalSize: data.length,
      compressedSize: compressed.length,
      algorithm: settings.algorithm,
      quality: settings.quality,
      format: 'mp3',
      compressionRatio: 1.0,
      timestamp: DateTime.now(),
    );
    
    return CompressionResult(data: compressed, metadata: metadata);
  }
  
  Future<CompressionResult> _compressGeneric(
    Uint8List data,
    CompressionSettings settings,
  ) async {
    // Generic compression using deflate
    final compressed = await _deflateCompress(data, settings.quality);
    
    final metadata = CompressionMetadata(
      originalSize: data.length,
      compressedSize: compressed.length,
      algorithm: 'generic_deflate',
      quality: settings.quality,
      format: 'generic',
      compressionRatio: compressed.length / data.length,
      timestamp: DateTime.now(),
    );
    
    return CompressionResult(data: compressed, metadata: metadata);
  }
  
  Future<Uint8List> _decompressPCM(
    Uint8List data,
    CompressionMetadata? metadata,
  ) async {
    return await _lz4Decompress(data);
  }
  
  Future<Uint8List> _decompressWAV(
    Uint8List data,
    CompressionMetadata? metadata,
  ) async {
    return await _deflateDecompress(data);
  }
  
  Future<Uint8List> _decompressMP3(
    Uint8List data,
    CompressionMetadata? metadata,
  ) async {
    // MP3 decompression would involve decoding
    // For now, return the data as-is
    return data;
  }
  
  Future<Uint8List> _decompressGeneric(
    Uint8List data,
    CompressionMetadata? metadata,
  ) async {
    return await _deflateDecompress(data);
  }
  
  // Simulated compression algorithms
  
  Future<Uint8List> _lz4Compress(Uint8List data, double quality) async {
    // Simulate LZ4 compression
    final compressionRatio = 0.4 + (quality * 0.4);
    final targetSize = (data.length * compressionRatio).round();
    
    // Simple simulation - in practice would use real LZ4
    final compressed = Uint8List(targetSize);
    for (int i = 0; i < targetSize; i++) {
      compressed[i] = data[i % data.length];
    }
    
    return compressed;
  }
  
  Future<Uint8List> _lz4Decompress(Uint8List data) async {
    // Simulate LZ4 decompression
    // In practice, this would restore the original data
    return data;
  }
  
  Future<Uint8List> _deflateCompress(Uint8List data, double quality) async {
    // Simulate deflate compression
    final compressionRatio = 0.3 + (quality * 0.5);
    final targetSize = (data.length * compressionRatio).round();
    
    final compressed = Uint8List(targetSize);
    for (int i = 0; i < targetSize; i++) {
      compressed[i] = data[i % data.length];
    }
    
    return compressed;
  }
  
  Future<Uint8List> _deflateDecompress(Uint8List data) async {
    // Simulate deflate decompression
    return data;
  }
  
  void _updateCompressionStats({
    required int originalSize,
    required int compressedSize,
    required Duration duration,
  }) {
    _totalCompressions++;
    _bytesCompressed += originalSize;
    _bytesSaved += (originalSize - compressedSize);
  }
  
  void _updateDecompressionStats({
    required int compressedSize,
    required int decompressedSize,
    required Duration duration,
  }) {
    _totalDecompressions++;
    _bytesDecompressed += decompressedSize;
  }
}

/// Compression settings
class CompressionSettings {
  final String algorithm;
  final double quality;
  final bool enableVBR;
  final int targetBitrate;
  
  const CompressionSettings({
    required this.algorithm,
    required this.quality,
    required this.enableVBR,
    required this.targetBitrate,
  });
  
  CompressionSettings copyWith({
    String? algorithm,
    double? quality,
    bool? enableVBR,
    int? targetBitrate,
  }) {
    return CompressionSettings(
      algorithm: algorithm ?? this.algorithm,
      quality: quality ?? this.quality,
      enableVBR: enableVBR ?? this.enableVBR,
      targetBitrate: targetBitrate ?? this.targetBitrate,
    );
  }
}

/// Compression metadata
class CompressionMetadata {
  final int originalSize;
  final int compressedSize;
  final String algorithm;
  final double quality;
  final String format;
  final double compressionRatio;
  final DateTime timestamp;
  
  const CompressionMetadata({
    required this.originalSize,
    required this.compressedSize,
    required this.algorithm,
    required this.quality,
    required this.format,
    required this.compressionRatio,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() {
    return {
      'original_size': originalSize,
      'compressed_size': compressedSize,
      'algorithm': algorithm,
      'quality': quality,
      'format': format,
      'compression_ratio': compressionRatio,
      'timestamp': timestamp.toIso8601String(),
    };
  }
  
  factory CompressionMetadata.fromJson(Map<String, dynamic> json) {
    return CompressionMetadata(
      originalSize: json['original_size'],
      compressedSize: json['compressed_size'],
      algorithm: json['algorithm'],
      quality: (json['quality'] as num).toDouble(),
      format: json['format'],
      compressionRatio: (json['compression_ratio'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

/// Compression result
class CompressionResult {
  final Uint8List data;
  final CompressionMetadata metadata;
  
  const CompressionResult({
    required this.data,
    required this.metadata,
  });
}

/// Compression statistics
class CompressionStatistics {
  final int totalCompressions;
  final int totalDecompressions;
  final int totalBytesCompressed;
  final int totalBytesDecompressed;
  final int totalBytesSaved;
  final double averageCompressionRatio;
  final int cacheSize;
  
  const CompressionStatistics({
    required this.totalCompressions,
    required this.totalDecompressions,
    required this.totalBytesCompressed,
    required this.totalBytesDecompressed,
    required this.totalBytesSaved,
    required this.averageCompressionRatio,
    required this.cacheSize,
  });
  
  double get spaceSavedPercentage {
    return totalBytesCompressed > 0 
        ? (totalBytesSaved / totalBytesCompressed) * 100
        : 0.0;
  }
  
  Map<String, dynamic> toJson() {
    return {
      'total_compressions': totalCompressions,
      'total_decompressions': totalDecompressions,
      'total_bytes_compressed': totalBytesCompressed,
      'total_bytes_decompressed': totalBytesDecompressed,
      'total_bytes_saved': totalBytesSaved,
      'average_compression_ratio': averageCompressionRatio,
      'cache_size': cacheSize,
      'space_saved_percentage': spaceSavedPercentage,
    };
  }
}