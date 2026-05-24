class ApiConfig {
  ApiConfig._();

  /// 编译期注入：flutter run --dart-define-from-file=config.json
  /// 未指定时回退到 localhost:8080
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://localhost:8080',
  );

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
  static String url(String path) => '$baseUrl$path';
}
