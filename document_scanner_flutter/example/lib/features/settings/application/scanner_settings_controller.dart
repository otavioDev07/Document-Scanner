import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ScannerSettingsStore {
  Future<bool?> getBool(String key);
  Future<int?> getInt(String key);
  Future<String?> getString(String key);
  Future<void> setBool(String key, bool value);
  Future<void> setInt(String key, int value);
  Future<void> setString(String key, String value);
}

final class SharedPreferencesScannerSettingsStore
    implements ScannerSettingsStore {
  SharedPreferencesScannerSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<bool?> getBool(String key) => _preferences.getBool(key);

  @override
  Future<int?> getInt(String key) => _preferences.getInt(key);

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);

  @override
  Future<void> setInt(String key, int value) => _preferences.setInt(key, value);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);
}

final class MemoryScannerSettingsStore implements ScannerSettingsStore {
  MemoryScannerSettingsStore([Map<String, Object>? values])
    : _values = <String, Object>{...?values};

  final Map<String, Object> _values;

  @override
  Future<bool?> getBool(String key) async => _values[key] as bool?;

  @override
  Future<int?> getInt(String key) async => _values[key] as int?;

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> setBool(String key, bool value) async => _values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;

  @override
  Future<void> setString(String key, String value) async =>
      _values[key] = value;
}

final class ScannerSettingsController extends ChangeNotifier {
  ScannerSettingsController({ScannerSettingsStore? store})
    : _store = store ?? SharedPreferencesScannerSettingsStore();

  static const String _autoCaptureKey = 'scanner.autoCapture';
  static const String _diagnosticsKey = 'scanner.diagnostics';
  static const String _jpegQualityKey = 'scanner.jpegQuality';
  static const String _localeKey = 'appearance.locale';

  final ScannerSettingsStore _store;

  bool _autoCapture = true;
  bool _diagnosticsEnabled = false;
  int _jpegQuality = 92;
  String? _localeId;

  bool get autoCapture => _autoCapture;
  bool get diagnosticsEnabled => _diagnosticsEnabled;
  int get jpegQuality => _jpegQuality;
  String? get localeId => _localeId;

  Future<void> load() async {
    _autoCapture = await _store.getBool(_autoCaptureKey) ?? true;
    _diagnosticsEnabled = await _store.getBool(_diagnosticsKey) ?? false;
    _jpegQuality = (await _store.getInt(_jpegQualityKey) ?? 92).clamp(60, 100);
    final String storedLocale = await _store.getString(_localeKey) ?? '';
    _localeId = storedLocale.isEmpty ? null : storedLocale;
    notifyListeners();
  }

  Future<void> setAutoCapture(bool value) async {
    if (_autoCapture == value) return;
    _autoCapture = value;
    notifyListeners();
    await _store.setBool(_autoCaptureKey, value);
  }

  Future<void> setDiagnosticsEnabled(bool value) async {
    if (_diagnosticsEnabled == value) return;
    _diagnosticsEnabled = value;
    notifyListeners();
    await _store.setBool(_diagnosticsKey, value);
  }

  Future<void> setJpegQuality(int value) async {
    final int normalized = value.clamp(60, 100);
    if (_jpegQuality == normalized) return;
    _jpegQuality = normalized;
    notifyListeners();
    await _store.setInt(_jpegQualityKey, normalized);
  }

  Future<void> setLocaleId(String? value) async {
    if (_localeId == value) return;
    _localeId = value;
    notifyListeners();
    await _store.setString(_localeKey, value ?? '');
  }
}
