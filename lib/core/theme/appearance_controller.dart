import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppearanceController extends ChangeNotifier {
  AppearanceController({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  static final instance = AppearanceController();
  static const storageKey = 'gather2gether.appearance';
  final FlutterSecureStorage _storage;
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  String get label => switch (_mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };

  Future<void> load() async {
    try {
      final saved = await _storage.read(key: storageKey);
      _mode =
          ThemeMode.values.where((mode) => mode.name == saved).firstOrNull ??
          ThemeMode.system;
      notifyListeners();
    } catch (_) {
      // An unavailable preference store must not prevent the app from opening.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    final previous = _mode;
    _mode = mode;
    notifyListeners();
    try {
      await _storage.write(key: storageKey, value: mode.name);
    } catch (_) {
      _mode = previous;
      notifyListeners();
      rethrow;
    }
  }
}
