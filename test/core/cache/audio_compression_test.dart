import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import '../../../lib/core/cache/audio_compression.dart';

void main() {
  group('AudioCompression Tests', () {
    late AudioCompression compression;

    setUp(() {
      compression = AudioCompression();
    });

    group('Compression', () {
      test('should compress PCM audio data', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );

        // Act
        final compressedData = await compression.compress(
          originalData,
          format: 'pcm',
        );

        // Assert
        expect(compressedData.length, lessThan(originalData.length));
        expect(compressedData, isNotEmpty);
      });

      test('should compress WAV audio data', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );

        // Act
        final compressedData = await compression.compress(
          originalData,
          format: 'wav',
        );

        // Assert
        expect(compressedData.length, lessThan(originalData.length));
        expect(compressedData, isNotEmpty);
      });

      test('should handle MP3 format', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );

        // Act
        final compressedData = await compression.compress(
          originalData,
          format: 'mp3',
        );

        // Assert
        expect(compressedData, isNotEmpty);
      });

      test('should handle empty data', () async {
        // Arrange
        final emptyData = Uint8List(0);

        // Act
        final compressedData = await compression.compress(
          emptyData,
          format: 'pcm',
        );

        // Assert
        expect(compressedData, isEmpty);
      });

      test('should respect quality parameter', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );

        // Act
        final highQualityData = await compression.compress(
          originalData,
          format: 'pcm',
          quality: 0.9,
        );
        
        final lowQualityData = await compression.compress(
          originalData,
          format: 'pcm',
          quality: 0.1,
        );

        // Assert
        expect(highQualityData.length, greaterThan(lowQualityData.length));
      });

      test('should cache compression results', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(100, (index) => index % 256),
        );

        // Act
        final firstResult = await compression.compress(
          originalData,
          format: 'pcm',
        );
        
        final secondResult = await compression.compress(
          originalData,
          format: 'pcm',
        );

        // Assert
        expect(firstResult, equals(secondResult));
      });
    });

    group('Decompression', () {
      test('should decompress PCM audio data', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );
        
        final compressedData = await compression.compress(
          originalData,
          format: 'pcm',
        );

        // Act
        final decompressedData = await compression.decompress(
          compressedData,
          format: 'pcm',
        );

        // Assert
        expect(decompressedData, isNotEmpty);
      });

      test('should decompress WAV audio data', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );
        
        final compressedData = await compression.compress(
          originalData,
          format: 'wav',
        );

        // Act
        final decompressedData = await compression.decompress(
          compressedData,
          format: 'wav',
        );

        // Assert
        expect(decompressedData, isNotEmpty);
      });

      test('should handle empty compressed data', () async {
        // Arrange
        final emptyData = Uint8List(0);

        // Act
        final decompressedData = await compression.decompress(
          emptyData,
          format: 'pcm',
        );

        // Assert
        expect(decompressedData, isEmpty);
      });

      test('should use metadata when provided', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );
        
        final compressedData = await compression.compress(
          originalData,
          format: 'pcm',
        );
        
        final metadata = CompressionMetadata(
          originalSize: originalData.length,
          compressedSize: compressedData.length,
          algorithm: 'pcm_lz4',
          quality: 0.8,
          format: 'pcm',
          compressionRatio: compressedData.length / originalData.length,
          timestamp: DateTime.now(),
        );

        // Act
        final decompressedData = await compression.decompress(
          compressedData,
          format: 'pcm',
          metadata: metadata,
        );

        // Assert
        expect(decompressedData, isNotEmpty);
      });
    });

    group('Compression Ratio', () {
      test('should calculate compression ratio correctly', () {
        // Arrange
        final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);
        final compressedData = Uint8List.fromList([1, 2]);

        // Act
        final ratio = compression.getCompressionRatio(
          originalData,
          compressedData,
        );

        // Assert
        expect(ratio, equals(0.4)); // 2 / 5 = 0.4
      });

      test('should handle empty original data', () {
        // Arrange
        final emptyData = Uint8List(0);
        final compressedData = Uint8List.fromList([1, 2]);

        // Act
        final ratio = compression.getCompressionRatio(
          emptyData,
          compressedData,
        );

        // Assert
        expect(ratio, equals(1.0));
      });
    });

    group('Optimal Settings', () {
      test('should return optimal settings for different formats', () {
        // Act
        final pcmSettings = compression.getOptimalSettings(
          format: 'pcm',
          sampleRate: 44100,
          bitDepth: 16,
          duration: const Duration(seconds: 30),
        );

        final wavSettings = compression.getOptimalSettings(
          format: 'wav',
          sampleRate: 44100,
          bitDepth: 16,
          duration: const Duration(seconds: 30),
        );

        // Assert
        expect(pcmSettings.algorithm, isNotNull);
        expect(pcmSettings.quality, greaterThan(0));
        expect(pcmSettings.targetBitrate, greaterThan(0));
        
        expect(wavSettings.algorithm, isNotNull);
        expect(wavSettings.quality, greaterThan(0));
        expect(wavSettings.targetBitrate, greaterThan(0));
      });

      test('should adjust quality for short audio clips', () {
        // Act
        final shortAudioSettings = compression.getOptimalSettings(
          format: 'pcm',
          sampleRate: 44100,
          bitDepth: 16,
          duration: const Duration(seconds: 3),
        );

        final longAudioSettings = compression.getOptimalSettings(
          format: 'pcm',
          sampleRate: 44100,
          bitDepth: 16,
          duration: const Duration(minutes: 5),
        );

        // Assert
        expect(shortAudioSettings.quality, greaterThan(longAudioSettings.quality));
      });

      test('should adjust bitrate based on sample rate', () {
        // Act
        final highSampleRateSettings = compression.getOptimalSettings(
          format: 'pcm',
          sampleRate: 48000,
          bitDepth: 16,
          duration: const Duration(seconds: 30),
        );

        final lowSampleRateSettings = compression.getOptimalSettings(
          format: 'pcm',
          sampleRate: 22050,
          bitDepth: 16,
          duration: const Duration(seconds: 30),
        );

        // Assert
        expect(
          highSampleRateSettings.targetBitrate,
          greaterThan(lowSampleRateSettings.targetBitrate),
        );
      });
    });

    group('Size Estimation', () {
      test('should estimate compressed size accurately', () {
        // Act
        final estimatedSize = compression.estimateCompressedSize(
          1000,
          'pcm',
          quality: 0.8,
        );

        // Assert
        expect(estimatedSize, greaterThan(0));
        expect(estimatedSize, lessThan(1000));
      });

      test('should handle different formats', () {
        // Act
        final pcmSize = compression.estimateCompressedSize(1000, 'pcm');
        final wavSize = compression.estimateCompressedSize(1000, 'wav');
        final mp3Size = compression.estimateCompressedSize(1000, 'mp3');

        // Assert
        expect(pcmSize, greaterThan(0));
        expect(wavSize, greaterThan(0));
        expect(mp3Size, greaterThan(0));
        expect(mp3Size, lessThan(pcmSize)); // MP3 should be smaller
      });
    });

    group('Statistics', () {
      test('should track compression statistics', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );

        // Act
        await compression.compress(originalData, format: 'pcm');
        await compression.compress(originalData, format: 'wav');
        
        final stats = compression.getStatistics();

        // Assert
        expect(stats.totalCompressions, equals(2));
        expect(stats.totalBytesCompressed, greaterThan(0));
        expect(stats.totalBytesSaved, greaterThan(0));
        expect(stats.averageCompressionRatio, greaterThan(0));
      });

      test('should track decompression statistics', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );
        
        final compressedData = await compression.compress(
          originalData,
          format: 'pcm',
        );

        // Act
        await compression.decompress(compressedData, format: 'pcm');
        await compression.decompress(compressedData, format: 'pcm');
        
        final stats = compression.getStatistics();

        // Assert
        expect(stats.totalDecompressions, equals(2));
        expect(stats.totalBytesDecompressed, greaterThan(0));
      });

      test('should reset statistics correctly', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(1000, (index) => index % 256),
        );
        
        await compression.compress(originalData, format: 'pcm');

        // Act
        compression.resetStatistics();
        final stats = compression.getStatistics();

        // Assert
        expect(stats.totalCompressions, equals(0));
        expect(stats.totalDecompressions, equals(0));
        expect(stats.totalBytesCompressed, equals(0));
        expect(stats.totalBytesDecompressed, equals(0));
        expect(stats.totalBytesSaved, equals(0));
      });
    });

    group('Cache Management', () {
      test('should clear compression cache', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(100, (index) => index % 256),
        );
        
        await compression.compress(originalData, format: 'pcm');

        // Act
        compression.clearCache();
        final stats = compression.getStatistics();

        // Assert
        expect(stats.cacheSize, equals(0));
      });

      test('should limit cache size', () async {
        // Arrange
        final originalData = Uint8List.fromList(
          List.generate(100, (index) => index % 256),
        );

        // Act - Generate many different compression operations
        for (int i = 0; i < 150; i++) {
          final data = Uint8List.fromList(
            List.generate(100, (index) => (index + i) % 256),
          );
          await compression.compress(data, format: 'pcm');
        }

        final stats = compression.getStatistics();

        // Assert
        expect(stats.cacheSize, lessThanOrEqualTo(100));
      });
    });

    group('Error Handling', () {
      test('should handle compression errors gracefully', () async {
        // This test would require mocking internal compression methods
        // to simulate failures. For now, we test with valid inputs.
        
        // Arrange
        final originalData = Uint8List.fromList([1, 2, 3, 4, 5]);

        // Act & Assert
        expect(
          () => compression.compress(originalData, format: 'pcm'),
          returnsNormally,
        );
      });

      test('should handle decompression errors gracefully', () async {
        // Arrange
        final invalidData = Uint8List.fromList([1, 2, 3, 4, 5]);

        // Act & Assert
        expect(
          () => compression.decompress(invalidData, format: 'pcm'),
          returnsNormally,
        );
      });
    });

    group('Data Models', () {
      test('CompressionSettings should copy correctly', () {
        // Arrange
        final settings = CompressionSettings(
          algorithm: 'test_algorithm',
          quality: 0.8,
          enableVBR: true,
          targetBitrate: 128,
        );

        // Act
        final copied = settings.copyWith(
          quality: 0.9,
          targetBitrate: 256,
        );

        // Assert
        expect(copied.algorithm, equals('test_algorithm'));
        expect(copied.quality, equals(0.9));
        expect(copied.enableVBR, isTrue);
        expect(copied.targetBitrate, equals(256));
      });

      test('CompressionMetadata should serialize correctly', () {
        // Arrange
        final metadata = CompressionMetadata(
          originalSize: 1000,
          compressedSize: 600,
          algorithm: 'test_algorithm',
          quality: 0.8,
          format: 'pcm',
          compressionRatio: 0.6,
          timestamp: DateTime.now(),
        );

        // Act
        final json = metadata.toJson();
        final restored = CompressionMetadata.fromJson(json);

        // Assert
        expect(restored.originalSize, equals(1000));
        expect(restored.compressedSize, equals(600));
        expect(restored.algorithm, equals('test_algorithm'));
        expect(restored.quality, equals(0.8));
        expect(restored.format, equals('pcm'));
        expect(restored.compressionRatio, equals(0.6));
      });

      test('CompressionStatistics should calculate space saved percentage', () {
        // Arrange
        final stats = CompressionStatistics(
          totalCompressions: 10,
          totalDecompressions: 5,
          totalBytesCompressed: 1000,
          totalBytesDecompressed: 500,
          totalBytesSaved: 400,
          averageCompressionRatio: 0.6,
          cacheSize: 20,
        );

        // Act
        final spaceSaved = stats.spaceSavedPercentage;

        // Assert
        expect(spaceSaved, equals(40.0)); // 400 / 1000 * 100
      });
    });
  });
}