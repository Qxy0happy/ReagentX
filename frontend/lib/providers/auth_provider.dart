import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider extends ChangeNotifier {
  String? _userId;
  String? _userName;
  String? _userRole;
  String? _groupId;
  String? _groupName;
  String? _labLocation;
  String? _teacher;
  bool _loaded = false;

  List<Map<String, dynamic>> _allGroups = [];
  bool get isLoggedIn => _userId != null;
  bool get loaded => _loaded;
  List<Map<String, dynamic>> get allGroups => _allGroups;
  String? get userId => _userId;
  String? get userName => _userName;
  String? get userRole => _userRole;
  String? get groupId => _groupId;
  String? get groupName => _groupName;
  String? get labLocation => _labLocation;
  String? get teacher => _teacher;

  /// App 启动时调用：从本地恢复登录态
  Future<void> loadSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    _userName = prefs.getString('user_name');
    _userRole = prefs.getString('user_role');
    _groupId = prefs.getString('group_id');
    _groupName = prefs.getString('group_name');
    _labLocation = prefs.getString('lab_location');
    _teacher = prefs.getString('teacher');
    _loaded = true;
    notifyListeners();
  }

  void _saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', _userId ?? '');
    await prefs.setString('user_name', _userName ?? '');
    await prefs.setString('user_role', _userRole ?? '');
    await prefs.setString('group_id', _groupId ?? '');
    await prefs.setString('group_name', _groupName ?? '');
    await prefs.setString('lab_location', _labLocation ?? '');
    await prefs.setString('teacher', _teacher ?? '');
  }

  /// 拉取所有课题组列表并缓存到本地
  Future<void> fetchAllGroups() async {
    try {
      final resp = await http.get(
        Uri.parse('http://localhost:8080/api/v1/groups/suggest?q='),
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        _allGroups = (body['suggestions'] as List).cast<Map<String, dynamic>>();
        notifyListeners();
      }
    } catch (_) {}
  }

  // 注册
  Future<Map<String, dynamic>> register({
    required String teacherName,
    required String password,
    String memberPassword = '',
    String labLocation = '',
    List<String> members = const [],
    String serverUrl = 'http://localhost:8080',
  }) async {
    final resp = await http.post(
      Uri.parse('$serverUrl/api/v1/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'teacher_name': teacherName,
        'password': password,
        'member_password': memberPassword,
        'lab_location': labLocation,
        'members': members,
      }),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 201) {
      throw Exception(body['error'] ?? 'registration failed');
    }
    return body;
  }

  // 登录
  Future<void> login({
    required String teacherName,
    required String userName,
    required String password,
    String serverUrl = 'http://localhost:8080',
  }) async {
    final resp = await http.post(
      Uri.parse('$serverUrl/api/v1/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'teacher_name': teacherName,
        'user_name': userName,
        'password': password,
      }),
    );
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200) {
      throw Exception(body['error'] ?? 'login failed');
    }
    _userId = body['user_id'] as String;
    _userName = body['user_name'] as String;
    _userRole = body['role'] as String;
    _groupId = body['group_id'] as String;
    _groupName = body['group_name'] as String;
    _labLocation = body['lab_location'] as String? ?? '';
    _teacher = body['teacher'] as String;
    _saveSession();
    notifyListeners();
  }

  void logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _userId = null;
    _userName = null;
    _userRole = null;
    _groupId = null;
    _groupName = null;
    _labLocation = null;
    _teacher = null;
    notifyListeners();
  }
}
