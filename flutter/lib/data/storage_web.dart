import 'package:shared_preferences/shared_preferences.dart';

import 'storage.dart';

DocumentStore createStore() => _PrefsStore();

class _PrefsStore implements DocumentStore {
  static const _key = 'fittrack.document.v2';

  @override
  Future<String?> read() async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key);
    } catch (_) {
      return null; // Storage can be blocked (private window); the app still runs in memory.
    }
  }

  @override
  Future<void> write(String json) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, json);
    } catch (_) {}
  }
}
