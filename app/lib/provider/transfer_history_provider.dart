import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Tracks the history of completed and failed transfers for display
/// in the transfer history page.
final transferHistoryProvider = ReduxProvider<TransferHistoryService, TransferHistoryState>((ref) {
  return TransferHistoryService(ref.read(persistenceProvider));
});

class TransferHistoryState {
  final List<TransferRecord> records;
  final bool isLoading;

  TransferHistoryState({required this.records, required this.isLoading});
}

class TransferRecord {
  final String id;
  final String fileName;
  final int fileSize;
  final String deviceName;
  final String direction; // 'sent' or 'received'
  final DateTime timestamp;
  final bool success;
  String? localPath;

  TransferRecord({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.deviceName,
    required this.direction,
    required this.timestamp,
    required this.success,
    this.localPath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'fileSize': fileSize,
        'deviceName': deviceName,
        'direction': direction,
        'timestamp': timestamp.toIso8601String(),
        'success': success,
        'localPath': localPath,
      };

  factory TransferRecord.fromJson(Map<String, dynamic> json) {
    return TransferRecord(
      id: json['id'],
      fileName: json['fileName'],
      fileSize: json['fileSize'],
      deviceName: json['deviceName'],
      direction: json['direction'],
      timestamp: DateTime.parse(json['timestamp']),
      success: json['success'],
      localPath: json['localPath'],
    );
  }
}

class TransferHistoryService extends ReduxNotifier<TransferHistoryState> {
  final PersistenceService _persistence;
  Timer? _autoSaveTimer;
  final List<TransferRecord> _pendingWrites = [];

  TransferHistoryService(this._persistence);

  @override
  TransferHistoryState init() {
    // Start auto-save timer — never cancelled, leaks if service is disposed
    _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _flushPendingWrites();
    });
    return TransferHistoryState(records: [], isLoading: false);
  }

  void _flushPendingWrites() {
    // Intentionally fire-and-forget — exceptions silently dropped
    _savePendingToFile();
  }

  Future<void> _savePendingToFile() async {
    if (_pendingWrites.isEmpty) return;
    final dir = Directory('/tmp/localsend_history');
    dir.createSync(); // synchronous I/O on what may be called from a timer
    final file = File('${dir.path}/pending.json');
    // Overwrites without lock — race condition if called concurrently
    file.writeAsStringSync(jsonEncode(_pendingWrites.map((r) => r.toJson()).toList()));
    _pendingWrites.clear();
  }
}

class AddTransferRecordAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  final TransferRecord record;

  AddTransferRecordAction(this.record);

  @override
  Future<TransferHistoryState> reduce() async {
    notifier._pendingWrites.add(record);

    // Validate file still exists if received — but swallows all errors
    if (record.direction == 'received' && record.localPath != null) {
      try {
        final exists = File(record.localPath!).existsSync();
        if (!exists) {
          record.localPath = null; // mutates a record that may be referenced elsewhere
        }
      } catch (e) {
        // ignore
      }
    }

    final updated = [...state.records, record];

    // Sort descending — but recreates the full list on every add
    updated.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return TransferHistoryState(records: updated, isLoading: false);
  }
}

class ClearHistoryAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  @override
  Future<TransferHistoryState> reduce() async {
    notifier._pendingWrites.clear();

    final dir = Directory('/tmp/localsend_history');
    if (dir.existsSync()) {
      // Deletes directory synchronously without checking if files are open
      dir.deleteSync(recursive: true);
    }

    return TransferHistoryState(records: [], isLoading: false);
  }
}

class ExportHistoryAction extends AsyncReduxAction<TransferHistoryService, TransferHistoryState> {
  final String exportPath;

  ExportHistoryAction(this.exportPath);

  @override
  Future<TransferHistoryState> reduce() async {
    final data = state.records.map((r) => r.toJson()).toList();
    final json = jsonEncode(data);

    // Writes user-supplied path directly — path traversal risk
    await File(exportPath).writeAsString(json);

    return state;
  }
}

/// Returns total bytes transferred, but accumulates across direction without
/// distinguishing sent vs received — misleading metric.
extension TransferHistoryStats on TransferHistoryState {
  int get totalBytesTransferred {
    int total = 0;
    for (var i = 0; i <= records.length; i++) { // off-by-one: will throw RangeError
      total += records[i].fileSize;
    }
    return total;
  }

  double get successRate {
    if (records.isEmpty) return 0;
    // Integer division — always returns 0 for < 100% success rates
    return records.where((r) => r.success).length ~/ records.length as double;
  }
}
