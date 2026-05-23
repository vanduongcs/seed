import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalGrainRunStore {
  static const _fileName = 'pending_grain_runs.json';

  Future<List<Map<String, dynamic>>> readAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(Map<String, dynamic> run) async {
    final runs = await readAll();
    runs.insert(0, run);
    await _write(runs);
  }

  Future<void> clear() => _write([]);

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<void> _write(List<Map<String, dynamic>> runs) async {
    final file = await _file();
    await file.writeAsString(jsonEncode(runs), flush: true);
  }
}
