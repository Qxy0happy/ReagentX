import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

class InquiryProvider extends ChangeNotifier {
  int _pendingCount = 0;

  int get pendingCount => _pendingCount;

  Future<void> fetchPendingCount(String? userId) async {
    if (userId == null) {
      _pendingCount = 0;
      notifyListeners();
      return;
    }

    try {
      final resp = await http.get(
        ApiConfig.uri('/api/v1/users/$userId/inquiries'),
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final inquiries = body['inquiries'] as List;
        _pendingCount = inquiries.where((i) => i['status'] == 'pending').length;
        notifyListeners();
      }
    } catch (_) {
      // 静默失败，保持上次计数
    }
  }

  void clear() {
    _pendingCount = 0;
    notifyListeners();
  }
}
