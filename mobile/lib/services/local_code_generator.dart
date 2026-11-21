/// Offline per-device prefixed short numeric local code generator (SPEC_V2 §5.2).
///
/// Limitation: until per-worker counter blocks are leased from a central coordinator,
/// prefixes rely on a small per-install device prefix (e.g. 2 digits) plus sequence.
class LocalCodeGenerator {
  LocalCodeGenerator._();

  static String nextCode({
    required Iterable<String> existingCodes,
    int devicePrefix = 3,
  }) {
    final used = existingCodes.toSet();
    final safePrefix = devicePrefix <= 0 ? 1 : devicePrefix;
    var seq = 1;
    while (true) {
      final candidate = '$safePrefix${seq.toString().padLeft(3, '0')}';
      if (!used.contains(candidate)) {
        return candidate;
      }
      seq += 1;
    }
  }
}
