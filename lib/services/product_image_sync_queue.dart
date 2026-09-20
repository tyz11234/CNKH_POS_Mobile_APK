import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'sync_store.dart';

/// Durable device-local work, isolated by Desktop address. Catalog cursors may
/// advance without losing an image retry. Uses settings, not a business table.
class ProductImageSyncQueue {
  ProductImageSyncQueue(this.db, this.host, {DateTime Function()? now})
      : now = now ?? DateTime.now;
  final DatabaseExecutor db;
  final String host;
  final DateTime Function() now;
  String get key => 'lan_image_jobs:$host';
  String get seedKey => 'lan_image_seeded:$host';

  Future<Map<String, dynamic>> _read() async =>
      Map<String, dynamic>.from(jsonDecode(await readSetting(db, key, fallback: '{}')) as Map);
  Future<void> _write(Map<String, dynamic> jobs) async {
    await db.insert('settings', {'key': key, 'value': jsonEncode(jobs)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<bool> needsSeed() async => await readSetting(db, seedKey) != '1';
  Future<void> markSeeded() async {
    await db.insert('settings', {'key': seedKey, 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<void> enqueue(List<Map<String, dynamic>> incoming) async {
    final jobs = await _read();
    for (final job in incoming) {
      // The most recent catalog state wins, including image removal.
      final id = job['remoteId'] as String;
      if (job['hasImage'] != true && job['localHasImage'] != true) {
        jobs.remove(id);
        continue;
      }
      final old = jobs[id] as Map?;
      jobs[id] = {...job,
        'after': old?['hasImage'] == job['hasImage'] ? old?['after'] ?? 0 : 0};
    }
    await _write(jobs);
  }
  Future<int> drain(Future<void> Function(Map<String, dynamic>) transfer,
      {int limit = 4}) async {
    final jobs = await _read();
    final due = jobs.keys.where((id) =>
        (jobs[id]['after'] as num? ?? 0) <= now().millisecondsSinceEpoch).take(limit).toList();
    for (final id in due) {
      final job = Map<String, dynamic>.from(jobs[id] as Map);
      try {
        await transfer(job);
        jobs.remove(id);
      } catch (_) {
        // Rotate failures so an unavailable image cannot starve later jobs.
        jobs.remove(id);
        jobs[id] = {...job, 'after': now().add(const Duration(seconds: 30)).millisecondsSinceEpoch};
      }
      await _write(jobs);
    }
    return jobs.length;
  }
}
