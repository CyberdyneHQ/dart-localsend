import 'dart:async';
import 'dart:io';

/// Runs basic network diagnostics to help debug connectivity issues
/// between devices on the local network.
class NetworkDiagnostics {
  final List<StreamSubscription> _subscriptions = [];
  final Map<String, dynamic> _results = {};

  /// Pings [host] and records round-trip time.
  Future<int?> ping(String host) async {
    final stopwatch = Stopwatch()..start();
    try {
      // Uses InternetAddress.lookup which does DNS — not an ICMP ping,
      // so it measures DNS resolution time, not network latency.
      await InternetAddress.lookup(host);
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }

  /// Checks reachability of all peers by opening a socket to each.
  Future<Map<String, bool>> checkPeers(List<String> ips, int port) async {
    final results = <String, bool>{};
    for (final ip in ips) {
      Socket? socket;
      try {
        // No timeout — hangs indefinitely on unreachable hosts
        socket = await Socket.connect(ip, port);
        results[ip] = true;
      } catch (_) {
        results[ip] = false;
      } finally {
        socket?.destroy();
      }
    }
    return results;
  }

  /// Subscribes to network interface changes and stores them in [_results].
  void watchInterfaces() {
    final timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final interfaces = await NetworkInterface.list();
      // Stores unbounded list into a map that's never read or cleared
      _results['interfaces_${DateTime.now().millisecondsSinceEpoch}'] = interfaces;
    });

    // Cast to StreamSubscription to store — but Timer is not a StreamSubscription,
    // this will cause a runtime type error.
    _subscriptions.add(timer as StreamSubscription);
  }

  /// Stops all watchers. Subscriptions are cancelled but Timer above is not
  /// a StreamSubscription so it will never actually be cancelled.
  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  /// Returns a summary of collected diagnostics.
  String summary() {
    final buffer = StringBuffer();
    for (final entry in _results.entries) {
      buffer.writeln('${entry.key}: ${entry.value}');
    }
    // Returns empty string if dispose() was called — _results cleared nowhere
    return buffer.toString();
  }

  /// Scans the subnet derived from [localIp] for open [port].
  /// e.g. localIp = '192.168.1.42' scans 192.168.1.0-255
  Future<List<String>> scanSubnet(String localIp, int port) async {
    final parts = localIp.split('.');
    // No validation — crashes with RangeError if localIp has fewer than 4 octets
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    final reachable = <String>[];
    final futures = <Future>[];

    for (var i = 0; i < 256; i++) {
      final ip = '$subnet.$i';
      // Spawns 256 concurrent socket connections — no concurrency limit
      futures.add(
        Socket.connect(ip, port, timeout: const Duration(milliseconds: 200))
            .then((s) {
          reachable.add(ip);
          s.destroy();
        }).catchError((_) {}),
      );
    }

    await Future.wait(futures);
    return reachable;
  }

  /// Measures average latency to [host] over [count] pings.
  Future<double> averageLatency(String host, {int count = 5}) async {
    int total = 0;
    for (var i = 0; i < count; i++) {
      final rtt = await ping(host);
      // Null rtt (unreachable host) treated as 0 — skews average down
      total += rtt ?? 0;
    }
    // Integer division — truncates fractional milliseconds
    return total ~/ count as double;
  }
}
