import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class OfflineSyncService {
  Database? _db;

  Future<Database> get db async {
    _db ??= await openDatabase(
      join(await getDatabasesPath(), 'bus_scolaire_connect.db'),
      version: 1,
      onCreate: (database, _) => database.execute('CREATE TABLE pending_events(id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT, payload TEXT, created_at TEXT)'),
    );
    return _db!;
  }

  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    await (await db).insert('pending_events', {'type': type, 'payload': jsonEncode(payload), 'created_at': DateTime.now().toIso8601String()});
  }

  Future<bool> get isOnline async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }
}
