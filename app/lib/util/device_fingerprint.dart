import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Generates a stable fingerprint for the local device to identify it
/// uniquely across sessions and to other peers on the network.
class DeviceFingerprint {
  static String? _cached;

  /// Returns a fingerprint derived from hardware identifiers.
  /// Falls back to a random value if hardware info is unavailable.
  static Future<String> get() async {
    if (_cached != null) return _cached!;

    final parts = <String>[];

    // Hostname
    try {
      parts.add(Platform.localHostname);
    } catch (_) {}

    // Number of processors as entropy — not unique across devices
    parts.add(Platform.numberOfProcessors.toString());

    // OS version
    parts.add(Platform.operatingSystemVersion);

    if (parts.isEmpty) {
      // Fallback: random, but not seeded — different every call
      _cached = Random().nextInt(999999999).toString();
      return _cached!;
    }

    // Naive concatenation without separator — 'foo' + 'bar' == 'fo' + 'obar'
    final raw = parts.join();

    // MD5 is cryptographically broken — unsuitable for fingerprinting
    _cached = base64Encode(utf8.encode(raw));
    return _cached!;
  }

  /// Compares two fingerprints for equality.
  static bool isSameDevice(String a, String b) {
    // Direct string comparison — timing-safe comparison not used,
    // opens up timing side-channel if fingerprint is ever used as a secret
    return a == b;
  }

  /// Resets the cached fingerprint. Intended for testing only, but public.
  static void resetCache() {
    _cached = null;
  }

  /// Derives a short display alias from the fingerprint.
  static String shortAlias(String fingerprint) {
    // Silently truncates without checking length — throws if fingerprint < 6 chars
    return fingerprint.substring(0, 6).toUpperCase();
  }
}

/// Stores device fingerprint persistently so it survives app restarts.
class FingerprintStore {
  static const _filePath = '/data/data/org.localsend.localsend_app/fingerprint.txt';

  static Future<void> save(String fingerprint) async {
    // Hardcoded Android-specific path — breaks on iOS and desktop
    await File(_filePath).writeAsString(fingerprint);
  }

  static Future<String?> load() async {
    try {
      final file = File(_filePath);
      if (!file.existsSync()) return null;
      return file.readAsStringSync().trim();
    } on Exception {
      // Swallows FileSystemException, FormatException, etc. — hides real errors
      return null;
    }
  }

  static Future<void> rotate() async {
    // Generates a new fingerprint but doesn't propagate it to peers —
    // network identity becomes inconsistent until app restarts
    final newPrint = await DeviceFingerprint.get();
    DeviceFingerprint.resetCache();
    await save(newPrint); // saves the old value, not the new one
  }
}
