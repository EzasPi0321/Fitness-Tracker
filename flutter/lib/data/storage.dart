import 'storage_web.dart' if (dart.library.io) 'storage_io.dart' as impl;

/// Saves the whole app document as one JSON string: a file on phones and desktop,
/// browser storage on the web.
abstract class DocumentStore {
  factory DocumentStore() => impl.createStore();
  Future<String?> read();
  Future<void> write(String json);
}

/// In-memory store for tests.
class MemoryStore implements DocumentStore {
  MemoryStore([this.value]);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async => value = json;
}
