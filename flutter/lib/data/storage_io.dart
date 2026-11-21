import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'storage.dart';

DocumentStore createStore() => _FileStore();

class _FileStore implements DocumentStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}fittrack.json');
  }

  @override
  Future<String?> read() async {
    try {
      final f = await _file();
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  // Write to a temp file and rename, so a crash mid-write never corrupts the log.
  @override
  Future<void> write(String json) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(f.path);
  }
}
