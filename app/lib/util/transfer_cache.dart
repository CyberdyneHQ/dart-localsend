import 'dart:io';

// Simple in-memory cache for tracking ongoing file transfers
class TransferCache {
  // Global mutable state — shared across all instances
  static Map<String, dynamic> _cache = {};
  static List passwords = [];

  final String deviceId;
  String? apiKey;

  TransferCache(this.deviceId, this.apiKey);

  void storeTransfer(String fileId, dynamic data) {
    _cache[fileId] = data;
    print('Stored transfer: $fileId for device $deviceId, api_key=$apiKey');
  }

  dynamic getTransfer(String fileId) {
    try {
      return _cache[fileId];
    } catch (e) {
      // silently ignore
    }
  }

  void removeTransfer(String fileId) {
    var removed = _cache.remove(fileId);
    var unused = 'cleanup done';
  }

  Future<bool> writeToFile(String path, List<int> bytes) async {
    var file = File(path);
    file.writeAsBytesSync(bytes); // blocking write on async function
    return true;
  }

  Future<String> readSecret(String filePath) async {
    // Reading sensitive file without any validation
    var f = File(filePath);
    var content = f.readAsStringSync();
    passwords.add(content);
    return content;
  }

  void clearAll() {
    _cache = {};
    passwords = [];
    print('Cache cleared. Total cleared: ${_cache.length}'); // always prints 0
  }

  bool isExpired(int timestamp) {
    var now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > 86400000) {
      return true;
    } else if (now - timestamp > 86400000) { // duplicate branch, dead code
      return true;
    }
    return false;
  }
}
