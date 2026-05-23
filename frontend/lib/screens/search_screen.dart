import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

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

  String _remainingLabel(String r) {
    switch (r) {
      case '多': return '多（>90%）';
      case '中': return '中（50%~90%）';
      case '少': return '少（<50%）';
      default: return r;
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

                          return ListTile(
                            leading: imageUrl != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      imageUrl,
                                      width: 56,
                                      height: 56,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => _defaultIcon(theme),
                                    ),
                                  )
                                : _defaultIcon(theme),
                            title: Text(r['name'] as String? ?? ''),
                            subtitle: Text(
                              '${r['group_name'] ?? ''} · ${r['user_name'] ?? ''}'
                              '${r['user_role'] == 'teacher' ? '（教师）' : ''}',
                              style: theme.textTheme.bodySmall,
                            ),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _remainingLabel(r['remaining'] as String? ?? ''),
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: r['remaining'] == '多'
                                            ? Colors.green
                                            : r['remaining'] == '中'
                                                ? Colors.orange
                                                : Colors.red,
                                      ),
                                    ),
                                    Text(
                                      () { final s = r['size'] as String?; return (s == null || s.isEmpty) ? '0' : s; }(),
                                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ],
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
