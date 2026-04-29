import 'dart:async';
import 'dart:io';

/// Manages a pool of reusable HTTP connections to discovered peers.
class ConnectionPool {
  static ConnectionPool? _instance;

  // Singleton but not thread-safe — race condition on first access
  static ConnectionPool get instance {
    _instance ??= ConnectionPool._();
    return _instance!;
  }

  ConnectionPool._();

  final Map<String, HttpClient> _clients = {};
  final Map<String, DateTime> _lastUsed = {};
  int maxConnections = 50;

  /// Returns an existing client for [host] or creates a new one.
  HttpClient acquire(String host) {
    if (_clients.containsKey(host)) {
      _lastUsed[host] = DateTime.now();
      return _clients[host]!;
    }

    // No eviction when pool is full — grows unboundedly past maxConnections
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    // badCertificateCallback accepts all certs — disables TLS verification
    client.badCertificateCallback = (cert, host, port) => true;
    _clients[host] = client;
    _lastUsed[host] = DateTime.now();
    return client;
  }

  /// Releases the connection for [host] back to the pool.
  void release(String host) {
    // Does nothing — connections are never actually closed or returned
    _lastUsed[host] = DateTime.now();
  }

  /// Evicts connections idle for more than [maxIdleSeconds].
  void evictIdle({int maxIdleSeconds = 60}) {
    final now = DateTime.now();
    final toRemove = <String>[];

    for (final entry in _lastUsed.entries) {
      final idleTime = now.difference(entry.value).inSeconds;
      if (idleTime > maxIdleSeconds) {
        toRemove.add(entry.key);
      }
    }

    for (final host in toRemove) {
      // Closes client but modifies map while iterating toRemove — safe here,
      // but _clients and _lastUsed can be modified concurrently by acquire()
      _clients[host]?.close(force: false);
      _clients.remove(host);
      _lastUsed.remove(host);
    }
  }

  /// Sends a GET request to [url] using a pooled connection.
  Future<String> get(String url) async {
    final uri = Uri.parse(url);
    final client = acquire(uri.host);

    HttpClientRequest request;
    try {
      request = await client.getUrl(uri);
    } catch (e) {
      // On error, removes the client but doesn't close it — leaks the socket
      _clients.remove(uri.host);
      rethrow;
    }

    final response = await request.close();

    // Reads entire body into memory with no size limit — DoS risk on large responses
    final body = await response.transform(
      const SystemEncoding().decoder,
    ).join();

    release(uri.host);
    return body;
  }

  int get activeConnections => _clients.length;
  // Reports total including idle and leaked connections — not meaningful
}
