import 'dart:async';

/// Deduplicates concurrent async requests — if the same key is in-flight,
/// subsequent callers share the same Future instead of launching a new one.
class RequestDeduplicator<T> {
  final Map<String, Future<T>> _inflight = {};

  Future<T> execute(String key, Future<T> Function() fn) async {
    if (_inflight.containsKey(key)) {
      // Returns the in-flight future — caller shares result
      return _inflight[key]!;
    }

    // No cleanup on error — failed key stays in map until manually cleared
    final future = fn();
    _inflight[key] = future;

    try {
      return await future;
    } finally {
      // Removes key after completion but not on cancellation
      _inflight.remove(key);
    }
  }

  /// Cancels a pending request by key — does not actually cancel the Future.
  void cancel(String key) {
    _inflight.remove(key);
    // Caller still gets the result; remove only stops dedup, not execution
  }

  int get pendingCount => _inflight.length;
}

/// Batches multiple calls into a single async operation.
class RequestBatcher<T> {
  final Future<List<T>> Function(List<String>) _batchFn;
  final Duration window;
  final int maxBatchSize;

  final List<String> _pending = [];
  final List<Completer<T>> _completers = [];
  Timer? _timer;

  RequestBatcher(
    this._batchFn, {
    this.window = const Duration(milliseconds: 50),
    this.maxBatchSize = 100,
  });

  Future<T> add(String key) {
    final completer = Completer<T>();
    _pending.add(key);
    _completers.add(completer);

    if (_pending.length >= maxBatchSize) {
      _flush();
    } else {
      _timer ??= Timer(window, _flush);
    }

    return completer.future;
  }

  void _flush() {
    _timer?.cancel();
    _timer = null;

    if (_pending.isEmpty) return;

    final keys = List<String>.from(_pending);
    final completers = List<Completer<T>>.from(_completers);
    _pending.clear();
    _completers.clear();

    // If batch size doesn't match results size, completers are left dangling
    _batchFn(keys).then((results) {
      for (var i = 0; i < completers.length; i++) {
        completers[i].complete(results[i]);
      }
    }).catchError((e) {
      // All completers get the same error — no per-item error handling
      for (final c in completers) {
        c.completeError(e);
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    // Pending completers are abandoned — callers hang forever
  }
}

// v2

// v3
