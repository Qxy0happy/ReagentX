import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'config/api_config.dart';
import 'providers/auth_provider.dart';
import 'providers/inquiry_provider.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/publish_screen.dart';
import 'screens/login_screen.dart';

class ReagentXApp extends StatelessWidget {
  const ReagentXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ReagentX',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1565C0),
        useMaterial3: true,
      ),
    );
  }
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    ShellRoute(
      builder: (context, state, child) => HomeScreen(child: child),
      routes: [
        GoRoute(
          path: '/',
          redirect: (context, state) => '/search',
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: SearchScreen(),
          ),
        ),
        GoRoute(
          path: '/publish',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: _AuthGuard(child: PublishScreen()),
          ),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: _ProfilePage(),
          ),
        ),
      ],
    ),
    GoRoute(
      path: '/camera',
      builder: (context, state) => const CameraScreen(),
    ),
  ],
);

/// _AuthGuard 未登录时显示登录引导页，已登录则透传子页面
class _AuthGuard extends StatelessWidget {
  final Widget child;
  const _AuthGuard({required this.child});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoggedIn) return child;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text('请先登录', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('发布和查看个人信息需要登录', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.go('/login'),
              icon: const Icon(Icons.login),
              label: const Text('去登录'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/search'),
              child: const Text('先逛逛'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePage extends StatefulWidget {
  const _ProfilePage();

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  List<Map<String, dynamic>>? _items;
  List<Map<String, dynamic>>? _members;
  List<Map<String, dynamic>> _inquiries = [];
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAll();
    _loadInquiries();
  }

  Future<void> _loadAll() async {
    final auth = context.read<AuthProvider>();
    if (auth.userId == null || auth.groupId == null) return;
    setState(() => _loading = true);
    try {
      // 加载物品
      final itemsResp = await http.get(
        ApiConfig.uri('/api/v1/users/${auth.userId}/items'),
      );
      if (itemsResp.statusCode == 200) {
        _items = (jsonDecode(itemsResp.body)['items'] as List).cast<Map<String, dynamic>>();
      }
      // 加载课题组成员
      final groupResp = await http.get(
        ApiConfig.uri('/api/v1/groups/${auth.groupId}'),
      );
      if (groupResp.statusCode == 200) {
        _members = (jsonDecode(groupResp.body)['members'] as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteItem(int itemId) async {
    final auth = context.read<AuthProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除后无法恢复，确定要删除这个物品吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final resp = await http.delete(
        ApiConfig.uri('/api/v1/items/$itemId?owner_user_id=${auth.userId}'),
      );
      if (resp.statusCode == 200) {
        _loadAll();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('网络错误: $e')),
        );
      }
    }
  }

  Color _remainingColor(String r) {
    if (r == '多') return Colors.green;
    if (r == '中') return Colors.orange;
    return Colors.red;
  }

  String _remainingLabel(String r) {
    if (r == '多') return '多（>90%）';
    if (r == '中') return '中（50%~90%）';
    return '少（<50%）';
  }

  String _sizeText(String? s) => (s == null || s.isEmpty) ? '0' : s;

  Future<void> _changeRemaining(Map<String, dynamic> item) async {
    final current = item['remaining'] as String? ?? '多';
    final options = ['多', '中', '少'];
    final selected = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('修改剩余量'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((v) => ListTile(
            leading: Icon(
              v == current ? Icons.check_circle : Icons.radio_button_unchecked,
              color: v == current ? Colors.green : Colors.grey,
            ),
            title: Text(_remainingLabel(v)),
            onTap: () => Navigator.pop(ctx, v),
          )).toList(),
        ),
      ),
    );
    if (selected == null || selected == current) return;
    try {
      final resp = await http.patch(
        ApiConfig.uri('/api/v1/items/${item['id']}/remaining'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'remaining': selected}),
      );
      if (resp.statusCode == 200) {
        _loadAll();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('修改失败')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  Future<void> _changePassword() async {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('修改密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '新密码', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确认修改')),
        ],
      ),
    );
    if (confirmed != true) return;
    final oldPw = oldCtrl.text;
    final newPw = newCtrl.text;
    if (oldPw.isEmpty || newPw.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写完整')));
      return;
    }
    try {
      final auth = context.read<AuthProvider>();
      final resp = await http.put(
        ApiConfig.uri('/api/v1/users/${auth.userId}/password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'old_password': oldPw, 'new_password': newPw}),
      );
      final body = jsonDecode(resp.body);
      if (resp.statusCode == 200) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('密码已修改')));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(body['error'] ?? '修改失败')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  Future<void> _addMember() async {
    final ctrl = TextEditingController();
    final pwdCtrl = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('添加成员'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: '成员姓名', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: '设置密码（留空同教师密码）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, [ctrl.text.trim(), pwdCtrl.text]), child: const Text('添加')),
        ],
      ),
    );
    if (result == null || result.length < 2) return;
    final name = result[0];
    final password = result[1];
    try {
      final auth2 = context.read<AuthProvider>();
      final resp = await http.post(
        ApiConfig.uri('/api/v1/groups/${auth2.groupId}/members'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'password': password}),
      );
      if (resp.statusCode == 201) {
        _loadAll();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('添加失败')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  Future<void> _editMember(Map<String, dynamic> m) async {
    final ctrl = TextEditingController(text: m['name'] as String? ?? '');
    final name = await showDialog<String>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('修改成员姓名'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '新姓名', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('保存')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      final auth = context.read<AuthProvider>();
      final resp = await http.put(
        ApiConfig.uri('/api/v1/groups/${auth.groupId}/members/${m['id']}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      if (resp.statusCode == 200) {
        _loadAll();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('修改失败')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  Future<void> _deleteMember(Map<String, dynamic> m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => AlertDialog(
        title: const Text('删除成员'),
        content: Text('确定删除成员「${m['name']}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final auth = context.read<AuthProvider>();
      final resp = await http.delete(
        ApiConfig.uri('/api/v1/groups/${auth.groupId}/members/${m['id']}'),
      );
      if (resp.statusCode == 200) {
        _loadAll();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('删除失败')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('网络错误: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 用户信息卡片
          Center(
            child: Column(
              children: [
                Icon(Icons.account_circle, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                Text(auth.userName ?? '', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 2),
                Text(auth.groupName ?? '', style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 4),
                Chip(
                  label: Text(auth.userRole == 'teacher' ? '教师 👑' : '成员'),
                  visualDensity: VisualDensity.compact,
                ),
                if (auth.teacher != null && auth.teacher!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('指导教师: ${auth.teacher}', style: Theme.of(context).textTheme.bodySmall),
                ],
                if (auth.labLocation != null && auth.labLocation!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on_outlined, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(auth.labLocation!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _changePassword(),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('修改密码'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => auth.logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('退出登录'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 课题组成员
          Row(
            children: [
              Text('课题组成员', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                icon: Icon(Icons.person_add, size: 18),
                label: const Text('添加'),
                onPressed: auth.userRole == 'teacher'
                    ? () => _addMember()
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            ))
          else if (_members == null || _members!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('暂无成员', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._members!.map((m) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: Icon(
                  m['role'] == 'teacher' ? Icons.star : Icons.person,
                  color: m['role'] == 'teacher' ? Colors.amber : Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
                title: Text(m['name'] as String? ?? ''),
                subtitle: Text(m['role'] == 'teacher' ? '教师' : '成员',
                  style: Theme.of(context).textTheme.bodySmall),
                trailing: m['role'] != 'teacher'
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: auth.userRole == 'teacher'
                                ? () => _editMember(m)
                                : null,
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                            onPressed: auth.userRole == 'teacher'
                                ? () => _deleteMember(m)
                                : null,
                          ),
                        ],
                      )
                    : null,
              ),
            )),

          const SizedBox(height: 24),
          Text('我的发布', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          // 物品列表
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ))
          else if (_items == null || _items!.isEmpty)
            const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无发布', style: TextStyle(color: Colors.grey)),
            ))
          else
            ..._items!.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(Icons.science, color: Theme.of(context).colorScheme.primary),
                    title: Text(item['name'] as String? ?? ''),
                    subtitle: Text(
                      '${_sizeText(item['size'] as String?)} · ${_remainingLabel(item['remaining'] as String? ?? '')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _changeRemaining(item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _remainingColor(item['remaining'] as String? ?? '').withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item['remaining'] as String? ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _remainingColor(item['remaining'] as String? ?? ''),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(Icons.edit, size: 12,
                                  color: _remainingColor(item['remaining'] as String? ?? '')),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          color: Colors.red.shade300,
                          onPressed: () => _deleteItem(item['id'] as int),
                        ),
                      ],
                    ),
                  ),
                )),

          const SizedBox(height: 16),
          _buildInquiriesSection(),
        ],
      ),
    );
  }

  Future<void> _loadInquiries() async {
    final auth = context.read<AuthProvider>();
    if (auth.userId == null) return;
    try {
      final resp = await http.get(
        ApiConfig.uri('/api/v1/users/${auth.userId}/inquiries'),
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        _inquiries = (body['inquiries'] as List).cast<Map<String, dynamic>>();
        // 刷新 badge
        if (mounted) context.read<InquiryProvider>().fetchPendingCount(auth.userId);
      }
    } catch (_) {}
  }

  Widget _buildInquiriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('留言箱', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_inquiries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: Text('暂无留言', style: TextStyle(color: Colors.grey))),
          )
        else
          ..._inquiries.map((inq) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.message_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(inq['item_name'] as String? ?? '', style: Theme.of(context).textTheme.titleSmall),
                      const Spacer(),
                      Text(inq['created_at'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(inq['from_user_name'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      Text('留言', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                    ],
                  ),
                  if ((inq['message'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(inq['message'] as String? ?? '', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _statusChip(inq['status'] as String? ?? ''),
                      const Spacer(),
                      if (inq['status'] == 'pending')
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () => _updateInquiryStatus(inq['id'] as int, 'accepted'),
                              icon: const Icon(Icons.check, size: 14),
                              label: const Text('已联系', style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _updateInquiryStatus(inq['id'] as int, 'rejected'),
                              icon: const Icon(Icons.close, size: 14),
                              label: const Text('婉拒', style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                minimumSize: Size.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          )),
      ],
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'accepted' => ('已联系', Colors.green),
      'rejected' => ('已婉拒', Colors.grey),
      _ => ('待处理', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Future<void> _updateInquiryStatus(int id, String status) async {
    try {
      await http.patch(
        ApiConfig.uri('/api/v1/inquiries/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      _loadInquiries();
    } catch (_) {}
  }
}


