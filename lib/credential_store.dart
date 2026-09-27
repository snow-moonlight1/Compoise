import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Replaceable boundary for the one BYOK secret. Implementations must throw on
/// failed operations; null means no value, never an unreadable value.
abstract class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SystemCredentialStore implements CredentialStore {
  final String key;
  final FlutterSecureStorage storage;

  const SystemCredentialStore({
    this.key = 'matrixflow-custom-api-key',
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(migrateWithBackup: true),
    ),
  });

  @override
  Future<String?> read() => storage.read(key: key);

  @override
  Future<void> write(String value) => storage.write(key: key, value: value);

  @override
  Future<void> delete() => storage.delete(key: key);
}
