import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart SHA-256 digest utility for salted offline PIN verification (zero external deps).
class PinHasher {
  PinHasher._();

  static final Uint32List _initState = _computeSquareRootFractions();
  static final Uint32List _roundConstants = _computeCubeRootFractions();

  static List<int> _firstNPrimes(int count) {
    final primes = <int>[];
    var candidate = 2;
    while (primes.length < count) {
      var isPrime = true;
      for (final p in primes) {
        if (p * p > candidate) break;
        if (candidate % p == 0) {
          isPrime = false;
          break;
        }
      }
      if (isPrime) primes.add(candidate);
      candidate++;
    }
    return primes;
  }

  static Uint32List _computeSquareRootFractions() {
    final primes = _firstNPrimes(8);
    final out = Uint32List(8);
    for (var i = 0; i < 8; i++) {
      final root = math.sqrt(primes[i]);
      final frac = root - root.floorToDouble();
      out[i] = (frac * 4294967296.0).floor() & 0xFFFFFFFF;
    }
    return out;
  }

  static Uint32List _computeCubeRootFractions() {
    final primes = _firstNPrimes(64);
    final out = Uint32List(64);
    for (var i = 0; i < 64; i++) {
      final root = math.pow(primes[i], 1.0 / 3.0).toDouble();
      final frac = root - root.floorToDouble();
      out[i] = (frac * 4294967296.0).floor() & 0xFFFFFFFF;
    }
    return out;
  }

  static int _rotr(int x, int n) =>
      ((x & 0xFFFFFFFF) >>> n) | ((x << (32 - n)) & 0xFFFFFFFF);

  /// Return lowercase hex SHA-256 digest of salted `workerCode` + `pin`.
  static String hashPin(String workerCode, String pin) {
    final payload = 'asha_vaani_v2:${workerCode.trim().toLowerCase()}:${pin.trim()}';
    return sha256Hex(utf8.encode(payload));
  }

  /// Constant-time verification of `pin` against an expected lowercase hex digest.
  static bool verify(String workerCode, String pin, String expectedHex) {
    final actual = hashPin(workerCode, pin);
    if (actual.length != expectedHex.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual.codeUnitAt(i) ^ expectedHex.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Compute standard SHA-256 hex digest for arbitrary bytes.
  static String sha256Hex(List<int> input) {
    final bitLength = input.length * 8;
    final paddedLength = ((input.length + 9 + 63) ~/ 64) * 64;
    final data = Uint8List(paddedLength);
    data.setAll(0, input);
    data[input.length] = 0x80;
    final lenView = ByteData.sublistView(data);
    lenView.setUint64(paddedLength - 8, bitLength, Endian.big);

    final state = Uint32List.fromList(_initState);
    final schedule = Uint32List(64);
    final blockView = ByteData.sublistView(data);

    for (var offset = 0; offset < paddedLength; offset += 64) {
      for (var t = 0; t < 16; t++) {
        schedule[t] = blockView.getUint32(offset + t * 4, Endian.big);
      }
      for (var t = 16; t < 64; t++) {
        final s0 =
            _rotr(schedule[t - 15], 7) ^
            _rotr(schedule[t - 15], 18) ^
            (schedule[t - 15] >>> 3);
        final s1 =
            _rotr(schedule[t - 2], 17) ^
            _rotr(schedule[t - 2], 19) ^
            (schedule[t - 2] >>> 10);
        schedule[t] = (schedule[t - 16] + s0 + schedule[t - 7] + s1) & 0xFFFFFFFF;
      }

      var a = state[0];
      var b = state[1];
      var c = state[2];
      var d = state[3];
      var e = state[4];
      var f = state[5];
      var g = state[6];
      var h = state[7];

      for (var t = 0; t < 64; t++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final temp1 = (h + s1 + ch + _roundConstants[t] + schedule[t]) & 0xFFFFFFFF;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      state[0] = (state[0] + a) & 0xFFFFFFFF;
      state[1] = (state[1] + b) & 0xFFFFFFFF;
      state[2] = (state[2] + c) & 0xFFFFFFFF;
      state[3] = (state[3] + d) & 0xFFFFFFFF;
      state[4] = (state[4] + e) & 0xFFFFFFFF;
      state[5] = (state[5] + f) & 0xFFFFFFFF;
      state[6] = (state[6] + g) & 0xFFFFFFFF;
      state[7] = (state[7] + h) & 0xFFFFFFFF;
    }

    final sb = StringBuffer();
    for (final word in state) {
      sb.write(word.toRadixString(16).padLeft(8, '0'));
    }
    return sb.toString();
  }
}
