import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _updateUrl = 'https://cdn.jsdelivr.net/gh/Qxy0happy/ReagentX@main/update.json';

class UpdateInfo {
  final String version;
  final String releaseNotes;
  final Map<String, String> downloads;

  UpdateInfo({
    required this.version,
    required this.releaseNotes,
    required this.downloads,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String? ?? '',
      releaseNotes: json['release_notes'] as String? ?? '',
      downloads: (json['downloads'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          {},
    );
  }
}

class UpdateProvider extends ChangeNotifier {
  bool _checking = false;
  UpdateInfo? _latest;
  String? _error;

  bool get checking => _checking;
  UpdateInfo? get latest => _latest;
  String? get error => _error;

  /// 检查是否有新版本
  Future<bool> checkForUpdate() async {
    _checking = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await http.get(Uri.parse(_updateUrl)).timeout(
        const Duration(seconds: 10),
      );

      if (resp.statusCode != 200) {
        _error = '检查更新失败 (${resp.statusCode})';
        _checking = false;
        notifyListeners();
        return false;
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      _latest = UpdateInfo.fromJson(json);

      final currentVersion = await _getCurrentVersion();
      final hasUpdate = _compareVersions(currentVersion, _latest!.version);

      _checking = false;
      notifyListeners();
      return hasUpdate;
    } catch (e) {
      _error = '网络错误: $e';
      _checking = false;
      notifyListeners();
      return false;
    }
  }

  /// 用 url_launcher 在浏览器中打开对应平台的下载链接
  Future<void> download(String platform) async {
    final url = _latest?.downloads[platform];
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<String> _getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return 'v${info.version}';
    } catch (_) {
      return 'v0.0.0';
    }
  }

  /// 简单语义化版本比较：v0.1.7 > v0.1.6
  bool _compareVersions(String current, String latest) {
    final a = current.replaceAll(RegExp(r'^v'), '').split('.').map(int.parse).toList();
    final b = latest.replaceAll(RegExp(r'^v'), '').split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final va = i < a.length ? a[i] : 0;
      final vb = i < b.length ? b[i] : 0;
      if (va != vb) return va < vb;
    }
    return false;
  }
}
