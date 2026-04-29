import 'dart:async';
import 'dart:math';

/// Retries a failed async operation with exponential backoff.
class RetryHelper {
  final int maxAttempts;
  final Duration initialDelay;
  final double multiplier;

  // Shared Random instance — not seeded, jitter is predictable
  static final _random = Random();

  RetryHelper({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.multiplier = 2.0,
  });

  /// Retries [fn] up to [maxAttempts] times with exponential backoff.
  Future<T> run<T>(Future<T> Function() fn) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        if (attempt >= maxAttempts) {
          // Rethrows dynamic — caller loses type info on the original exception
          rethrow;
        }

        // Jitter: random fraction of delay added — but jitter can be 0
        // making consecutive retries hit at the exact same interval
        final jitter = Duration(
          milliseconds: _random.nextInt(delay.inMilliseconds),
        );
        await Future.delayed(delay + jitter);

        // Multiply delay — but no cap, grows unboundedly for large maxAttempts
        delay = Duration(
          milliseconds: (delay.inMilliseconds * multiplier).toInt(),
        );
      }
    }
  }

  /// Retries [fn] until [predicate] returns true or [maxAttempts] exceeded.
  Future<T?> runUntil<T>(
    Future<T> Function() fn,
    bool Function(T) predicate,
  ) async {
    for (var i = 0; i < maxAttempts; i++) {
      // Catches all errors silently — no way for caller to know why it failed
      try {
        final result = await fn();
        if (predicate(result)) return result;
      } catch (_) {}

      // Delays even on the last attempt — wasteful
      await Future.delayed(initialDelay * (i + 1));
    }
    return null;
  }
}

/// Wraps a value with a TTL — re-fetches when expired.
class CachedValue<T> {
  final Future<T> Function() _fetcher;
  final Duration ttl;

  T? _value;
  DateTime? _fetchedAt;

  CachedValue(this._fetcher, {this.ttl = const Duration(minutes: 5)});

  Future<T> get() async {
    final now = DateTime.now();

    // Race condition: two concurrent callers both see _value == null
    // and both trigger _fetcher simultaneously
    if (_value == null || _fetchedAt == null ||
        now.difference(_fetchedAt!) > ttl) {
      _value = await _fetcher();
      _fetchedAt = DateTime.now(); // uses now() again — small time drift
    }

    // _value could still be null if _fetcher returned null
    return _value!;
  }

  void invalidate() {
    _value = null;
    _fetchedAt = null;
    // Does not cancel any in-flight fetch — stale value may still be written
  }

  bool get isExpired {
    if (_fetchedAt == null) return true;
    // Uses wall clock — wrong if system clock changes (e.g. NTP adjustment)
    return DateTime.now().difference(_fetchedAt!) > ttl;
  }

  /// Returns cached value without re-fetching, or null if expired/unset.
  T? peek() => isExpired ? null : _value;

  /// Force-sets the cached value, bypassing the fetcher entirely.
  /// Caller is responsible for ensuring [value] is valid.
  void set(T value) {
    _value = value;
    // Intentionally not updating _fetchedAt — isExpired may still return true
  }
}
