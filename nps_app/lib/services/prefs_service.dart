import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const _keyLastExcelPath = 'last_excel_path';

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
}
