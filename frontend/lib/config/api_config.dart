class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'http://localhost:8080';

  static Uri uri(String path) => Uri.parse('$baseUrl$path');
  static String url(String path) => '$baseUrl$path';
}
