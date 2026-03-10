import 'package:shared_preferences/shared_preferences.dart';
import 'llm_provider.dart';

class PrefsService {
  static const _keyLastExcelPath = 'last_excel_path';
  static const _keyLastLinkedInPath = 'last_linkedin_path';
  static const _keyLastExcelDir = 'last_excel_dir';
  static const _keyLastLinkedInDir = 'last_linkedin_dir';
  static const _keyLastOutputDir = 'last_output_dir';
  static const _keySelectedProvider = 'selected_llm_provider';

  // ── Last file paths (for "Use Last" feature) ──────────────────────────

  static Future<String?> getLastExcelPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastExcelPath);
  }

  static Future<void> saveLastExcelPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastExcelPath, path);
  }

  static Future<void> clearLastExcelPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastExcelPath);
  }

  static Future<String?> getLastLinkedInPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLastLinkedInPath);
  }

  static Future<void> saveLastLinkedInPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastLinkedInPath, path);
  }

  static Future<void> clearLastLinkedInPath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastLinkedInPath);
  }

  // ── Last picker directories ────────────────────────────────────────────

  static Future<String?> getLastDir(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> saveLastDir(String key, String dir) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, dir);
  }

  static String get keyExcelDir => _keyLastExcelDir;
  static String get keyLinkedInDir => _keyLastLinkedInDir;
  static String get keyOutputDir => _keyLastOutputDir;

  // ── Per-provider API keys ─────────────────────────────────────────────

  static Future<String?> getApiKey(LlmProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(provider.prefsKey);
  }

  static Future<void> saveApiKey(LlmProvider provider, String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(provider.prefsKey, key);
  }

  // ── Selected provider ─────────────────────────────────────────────────

  static Future<LlmProvider> getSelectedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_keySelectedProvider);
    if (s == null) return LlmProvider.openai;
    return LlmProvider.fromString(s);
  }

  static Future<void> saveSelectedProvider(LlmProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySelectedProvider, provider.name);
  }
}
