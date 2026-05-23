import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../providers/auth_provider.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q.trim()));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final resp = await http.get(
        ApiConfig.uri('/api/v1/search?q=${Uri.encodeQueryComponent(q)}'),
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _results = (body['results'] as List).cast<Map<String, dynamic>>();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _fmtTime(String s) {
    if (s.length >= 16) return s.substring(0, 16);
    return s;
  }

  String _remainingLabel(String r) {
    switch (r) {
      case '多': return '多（>67%）';
      case '中': return '中（33%~67%）';
      case '少': return '少（<33%）';
      default: return r;
    }
  }

  Future<void> _showInquireDialog(BuildContext context, Map<String, dynamic> item) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再留言')),
      );
      return;
    }

    final msgCtrl = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item['name']}'),
        content: TextField(
          controller: msgCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '说点什么…（选填）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, msgCtrl.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );

    if (msg == null) return;

    try {
      final resp = await http.post(
        ApiConfig.uri('/api/v1/items/${item['id']}/inquire?user_id=${auth.userId}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': msg}),
      );
      if (resp.statusCode == 201) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已发送留言，等待回复')),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('发送失败')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('网络错误: $e')),
        );
      }
    }
  }

  Widget _defaultIcon(ThemeData theme) {
    return Container(
      width: 56, height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.science, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: MediaQuery.of(context).padding.top + 8, bottom: 8,
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索试剂名称、CAS、标签...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          // 结果列表
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isEmpty ? '输入关键词搜索试剂' : '未找到匹配结果',
                          style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          final imagePath = r['image_path'] as String? ?? '';
                          final imageUrl = imagePath.isNotEmpty
                              ? ApiConfig.url('/$imagePath')
                              : null;

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // 图片
                                  imageUrl != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            imageUrl,
                                            width: 52,
                                            height: 52,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => _defaultIcon(theme),
                                          ),
                                        )
                                      : _defaultIcon(theme),
                                  const SizedBox(width: 12),
                                  // 文字信息
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r['name'] as String? ?? '',
                                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${r['group_name'] ?? ''} · ${r['user_name'] ?? ''}'
                                          '${r['user_role'] == 'teacher' ? '（课题负责人）' : ''}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        if ((r['updated_at'] as String? ?? '').isNotEmpty)
                                          Text(
                                            '上次更新：${_fmtTime(r['updated_at'] as String)}',
                                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11),
                                          ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              _remainingLabel(r['remaining'] as String? ?? ''),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: r['remaining'] == '多'
                                                    ? Colors.green
                                                    : r['remaining'] == '中'
                                                        ? Colors.orange
                                                        : Colors.red,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              () { final s = r['size'] as String?; return (s == null || s.isEmpty) ? '' : s; }(),
                                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // 我想要按钮
                                  FilledButton.tonalIcon(
                                    onPressed: () => _showInquireDialog(context, r),
                                    icon: const Icon(Icons.favorite_border, size: 16),
                                    label: const Text('我想要', style: TextStyle(fontSize: 12)),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      minimumSize: Size.zero,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
