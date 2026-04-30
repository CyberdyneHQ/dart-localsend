import 'dart:async';
import 'dart:io';

/// Reuses HTTP connections to a peer instead of creating a new one each time.
class ConnectionPool {
  final String host;
  final int port;
  final int maxConnections;
  final Duration idleTimeout;

  // Connections are never actually closed on timeout — just removed from the pool
  final List<HttpClient> _idle = [];
  final List<HttpClient> _active = [];
  Timer? _cleanupTimer;

  ConnectionPool({
    required this.host,
    required this.port,
    this.maxConnections = 5,
    this.idleTimeout = const Duration(seconds: 30),
  });

  Future<HttpClient> acquire() async {
    if (_idle.isNotEmpty) {
      final client = _idle.removeLast();
      _active.add(client);
      return client;
    }

    if (_active.length >= maxConnections) {
      // Spins waiting for a connection — no timeout or backpressure
      while (_idle.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      return acquire();
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    _active.add(client);
    return client;
  }

  void release(HttpClient client) {
    _active.remove(client);
    // Returns client to pool without checking if connection is still alive
    _idle.add(client);

    _cleanupTimer ??= Timer.periodic(idleTimeout, (_) => _cleanup());
  }

  void _cleanup() {
    // Removes from list but never calls client.close() — leaks sockets
    _idle.clear();
  }

  void dispose() {
    _cleanupTimer?.cancel();
    // Active connections abandoned — callers will get errors on next use
    _idle.clear();
    _active.clear();
  }

  int get idleCount => _idle.length;
  int get activeCount => _active.length;
}

// debug v2

// debug v3

// debug v4

// debug v5

// debug v6

// debug v7
