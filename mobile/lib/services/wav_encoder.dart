import 'dart:math' as math;
import 'dart:typed_data';

/// Utilities for wrapping 16 kHz PCM16 mono audio streams in RIFF/WAVE containers
/// and computing normalized RMS audio levels for live UI meters (`SPEC_V2 §8`).
class WavEncoder {
  WavEncoder._();

  static const int defaultSampleRate = 16000;
  static const int numChannels = 1;
  static const int bitsPerSample = 16;

  static Uint8List encodePcm16Mono(
    Uint8List pcmBytes, {
    int sampleRate = defaultSampleRate,
  }) {
    final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final blockAlign = numChannels * (bitsPerSample ~/ 8);
    final dataLength = pcmBytes.length;
    final totalLength = 44 + dataLength;
    final header = ByteData(44);

    // RIFF header
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, 36 + dataLength, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt subchunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // PCM subchunk size
    header.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data subchunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataLength, Endian.little);

    final out = Uint8List(totalLength);
    out.setRange(0, 44, header.buffer.asUint8List());
    out.setRange(44, totalLength, pcmBytes);
    return out;
  }

  /// Normalized RMS loudness in `[0.0, 1.0]` for signed 16-bit LE PCM samples.
  static double computeAudioLevel(Uint8List pcmBytes) {
    final sampleCount = pcmBytes.length ~/ 2;
    if (sampleCount <= 0) return 0.0;
    final view = ByteData.sublistView(pcmBytes);
    var sumSquares = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = view.getInt16(i * 2, Endian.little).toDouble();
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / sampleCount);
    return (rms / 12000.0).clamp(0.0, 1.0);
  }
}
