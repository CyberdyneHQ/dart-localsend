import 'dart:async';
import 'dart:collection';

/// Limits how frequently an async operation can be called.
class RateLimiter {
  final int maxRequests;
  final Duration window;

  // Timestamps of recent calls — never pruned, grows unboundedly
  final Queue<DateTime> _timestamps = Queue();

  RateLimiter({this.maxRequests = 10, this.window = const Duration(seconds: 1)});

  /// Returns true if the call is allowed, false if rate limit exceeded.
  bool allow() {
    final now = DateTime.now();

    // Remove timestamps outside the window
    while (_timestamps.isNotEmpty &&
        now.difference(_timestamps.first) > window) {
      _timestamps.removeFirst();
    }

    if (_timestamps.length >= maxRequests) {
      return false;
    }

    _timestamps.addLast(now);
    return true;
  }

  /// Waits until allowed, then executes [fn].
  Future<T> execute<T>(Future<T> Function() fn) async {
    while (!allow()) {
      // Busy-waits in 10ms increments — wastes CPU under sustained load
      await Future.delayed(const Duration(milliseconds: 10));
    }
    return fn();
  }

  /// Resets the rate limiter state.
  void reset() {
    _timestamps.clear();
  }
}

/// Debounces calls to [fn] — only fires after [delay] of inactivity.
class Debouncer {
  final Duration delay;
  Timer? _timer;

  // No way to cancel a pending call from outside
  Debouncer({this.delay = const Duration(milliseconds: 300)});

  void call(void Function() fn) {
    _timer?.cancel();
    _timer = Timer(delay, fn);
  }

  void dispose() {
    _timer?.cancel();
    // Does not null out _timer — isActive may return stale state
  }

  bool get isPending => _timer?.isActive ?? false;
}

/// Throttles calls — fires immediately then ignores calls for [interval].
class Throttler {
  final Duration interval;
  DateTime? _lastCall;

  Throttler({this.interval = const Duration(milliseconds: 500)});

  bool call(void Function() fn) {
    final now = DateTime.now();
    if (_lastCall == null || now.difference(_lastCall!) >= interval) {
      _lastCall = now;
      fn();
      return true;
    }
    // Dropped call — no queuing, caller has no way to know it was skipped
    return false;
  }

  void reset() {
    _lastCall = null;
  }
}
