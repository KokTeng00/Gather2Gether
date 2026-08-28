import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(storageNamespace: 'gather2gether_auth'),
  iOptions: IOSOptions(
    accountName: 'com.gather2gether.auth',
    accessibility: KeychainAccessibility.unlocked_this_device,
  ),
  webOptions: WebOptions(
    dbName: 'Gather2GetherAuth',
    publicKey: 'Gather2GetherAuth',
  ),
);

class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _sessionKey = 'supabase_session';

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => _secureStorage.containsKey(key: _sessionKey);

  @override
  Future<String?> accessToken() => _secureStorage.read(key: _sessionKey);

  @override
  Future<void> persistSession(String persistSessionString) {
    return _secureStorage.write(key: _sessionKey, value: persistSessionString);
  }

  @override
  Future<void> removePersistedSession() {
    return _secureStorage.delete(key: _sessionKey);
  }
}

class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage();

  String _storageKey(String key) => 'pkce_$key';

  @override
  Future<String?> getItem({required String key}) {
    return _secureStorage.read(key: _storageKey(key));
  }

  @override
  Future<void> removeItem({required String key}) {
    return _secureStorage.delete(key: _storageKey(key));
  }

  @override
  Future<void> setItem({required String key, required String value}) {
    return _secureStorage.write(key: _storageKey(key), value: value);
  }
}
