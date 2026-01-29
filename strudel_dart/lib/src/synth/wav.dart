import 'dart:typed_data';

/// Utility for encoding PCM data into a WAV file buffer.
class WavEncoder {
  /// Encode stereo float buffers into a 16-bit PCM WAV byte buffer.
  static Uint8List encodePcm16Stereo({
    required Float32List left,
    required Float32List right,
    required int sampleRate,
  }) {
    if (left.length != right.length) {
      throw ArgumentError('Left/right buffers must have same length.');
    }

    const int numChannels = 2;
    const int bitsPerSample = 16;
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int byteRate = sampleRate * blockAlign;
    final int dataSize = left.length * blockAlign;
    final int chunkSize = 36 + dataSize;

    final header = ByteData(44);
    header.setUint32(0, 0x46464952, Endian.little); // RIFF
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint32(8, 0x45564157, Endian.little); // WAVE
    header.setUint32(12, 0x20746D66, Endian.little); // fmt 
    header.setUint32(16, 16, Endian.little); // PCM header size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint32(36, 0x61746164, Endian.little); // data
    header.setUint32(40, dataSize, Endian.little);

    final pcm = Int16List(left.length * 2);
    var idx = 0;
    for (var i = 0; i < left.length; i++) {
      final l = left[i].clamp(-1.0, 1.0);
      final r = right[i].clamp(-1.0, 1.0);
      pcm[idx++] = (l * 32767).round();
      pcm[idx++] = (r * 32767).round();
    }

    final output = BytesBuilder(copy: false);
    output.add(header.buffer.asUint8List());
    output.add(pcm.buffer.asUint8List());
    return output.takeBytes();
  }
}
