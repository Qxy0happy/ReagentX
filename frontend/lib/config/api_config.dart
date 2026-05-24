import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  ApiConfig._();

  static const String _defaultBaseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://localhost:8080',
  );

  /// 运行时 baseUrl，编译期默认值，可在设置页面修改
  static String baseUrl = _defaultBaseUrl;

  /// 从 SharedPreferences 加载用户设置的服务地址
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('server_url') ?? _defaultBaseUrl;
  }

  /// 保存服务地址到 SharedPreferences
  static Future<void> save(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    baseUrl = url;
  }

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
  static String url(String path) => '$baseUrl$path';
}
