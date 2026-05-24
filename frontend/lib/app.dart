import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'config/api_config.dart';
import 'providers/auth_provider.dart';
import 'providers/inquiry_provider.dart';
import 'providers/update_provider.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';
import 'screens/camera_screen.dart';
import 'screens/publish_screen.dart';

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
              onPressed: () => context.go('/profile'),
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
  List<Map<String, dynamic>> _myInquiries = [];
  bool _loading = false;
  bool _showArchived = false;
  bool _showMyArchived = false;

  // URL 校验
  String? _urlError;

  // 登录表单状态
  String _loginMode = 'login';
  final _groupCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _newTeacherCtrl = TextEditingController();
  final _newLabCtrl = TextEditingController();
  final _newUserCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  String _newRole = 'member';
  String? _loginError;

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().fetchAllGroups();
  }

  @override
  void dispose() {
    _groupCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _newTeacherCtrl.dispose();
    _newLabCtrl.dispose();
    _newUserCtrl.dispose();
    _newPwdCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAll();
    _loadInquiries();
    _loadMyInquiries();
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

  // --- 登录/注册逻辑 ---

  Future<void> _login() async {
    final teacherName = _groupCtrl.text.trim();
    final userName = _userCtrl.text.trim();
    final password = _pwdCtrl.text;
    if (teacherName.isEmpty || userName.isEmpty || password.isEmpty) {
      setState(() => _loginError = '请填写所有字段');
      return;
    }
    setState(() { _loading = true; _loginError = null; });
    try {
      await context.read<AuthProvider>().login(
        teacherName: teacherName,
        userName: userName,
        password: password,
      );
      if (mounted) {
        _groupCtrl.clear();
        _userCtrl.clear();
        _pwdCtrl.clear();
      }
    } catch (e) {
      if (mounted) setState(() => _loginError = '登录失败: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _register() async {
    if (_newTeacherCtrl.text.trim().isEmpty || _newUserCtrl.text.trim().isEmpty || _newPwdCtrl.text.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写所有必填项')));
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AuthProvider>().register(
        teacherName: _newTeacherCtrl.text.trim(),
        password: _newPwdCtrl.text,
        memberPassword: _newPwdCtrl.text,
        labLocation: _newLabCtrl.text.trim(),
        members: [_newUserCtrl.text.trim()],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('注册成功，请切换到登录')),
        );
        setState(() {
          _loginMode = 'login';
          _newTeacherCtrl.clear();
          _newLabCtrl.clear();
          _newUserCtrl.clear();
          _newPwdCtrl.clear();
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('注册失败: $e')));
    }
    if (mounted) setState(() => _loading = false);
  }

  // --- 物品管理 ---

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
    if (r == '多') return '多（>67%）';
    if (r == '中') return '中（33%~67%）';
    return '少（<33%）';
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
                hintText: '设置密码（留空同负责人密码）',
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

  Widget _buildLoginForm(AuthProvider auth) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24, right: 24,
          top: MediaQuery.of(context).padding.top + 48,
        ),
        child: Column(
          children: [
            Icon(Icons.science, size: 64, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text('ReagentX', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('课题组试剂管理平台', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 32),

            // 登录/注册 Tab
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'login', label: Text('登录')),
                ButtonSegment(value: 'register', label: Text('注册')),
              ],
              selected: {_loginMode},
              onSelectionChanged: (v) => setState(() => _loginMode = v.first),
            ),
            const SizedBox(height: 24),

            if (_loginMode == 'register') ...[
              TextField(
                controller: _newTeacherCtrl,
                decoration: const InputDecoration(labelText: '课题负责人 *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newLabCtrl,
                decoration: const InputDecoration(labelText: '实验室地址', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newUserCtrl,
                decoration: const InputDecoration(labelText: '您的姓名 *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _newRole,
                decoration: const InputDecoration(labelText: '角色 *', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'teacher', child: Text('课题负责人 👑')),
                  DropdownMenuItem(value: 'member', child: Text('成员')),
                ],
                onChanged: (v) => setState(() => _newRole = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码 *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _register,
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('注册'),
              ),
            ] else ...[
              TextField(
                controller: _groupCtrl,
                decoration: const InputDecoration(
                  labelText: '课题负责人',
                  hintText: '输入负责人姓名搜索课题组',
                  border: OutlineInputBorder(),
                ),
                onChanged: (q) {
                  if (q.length >= 1) context.read<AuthProvider>().fetchAllGroups();
                },
              ),
              Consumer<AuthProvider>(
                builder: (_, auth, __) {
                  final q = _groupCtrl.text.trim().toLowerCase();
                  if (q.isEmpty) return const SizedBox.shrink();
                  final filtered = auth.allGroups.where((s) =>
                    (s['teacher'] as String? ?? '').toLowerCase().contains(q) ||
                    (s['group_name'] as String? ?? '').toLowerCase().contains(q)
                  ).take(5).toList();
                  if (filtered.isEmpty) return const SizedBox.shrink();
                  return Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: filtered.map((s) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.group, size: 20),
                        title: Text(s['teacher'] as String? ?? ''),
                        subtitle: Text('${s['group_name']} · ${s['lab_location']}',
                          style: Theme.of(context).textTheme.bodySmall),
                        onTap: () {
                          _groupCtrl.text = s['teacher'] as String? ?? '';
                          _groupCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: _groupCtrl.text.length));
                        },
                      )).toList(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(labelText: '姓名 *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwdCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码 *', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 4),
              if (_loginError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_loginError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _login,
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('登录'),
              ),
            ],

            const SizedBox(height: 32),
            Text('ReagentX · 试剂管理平台', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) return _buildLoginForm(auth);

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
                  label: Text(auth.userRole == 'teacher' ? '课题负责人 👑' : '成员'),
                  visualDensity: VisualDensity.compact,
                ),
                if (auth.teacher != null && auth.teacher!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('课题负责人: ${auth.teacher}', style: Theme.of(context).textTheme.bodySmall),
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
                subtitle: Text(m['role'] == 'teacher' ? '课题负责人' : '成员',
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
          _buildSettingsSection(),
          const SizedBox(height: 16),
          _buildUpdateSection(),
          const SizedBox(height: 16),
          _buildMyInquiriesSection(),
          const SizedBox(height: 16),
          _buildInquiriesSection(),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('设置', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.dns_outlined, color: Theme.of(context).colorScheme.primary),
            title: const Text('服务器地址'),
            subtitle: Text(ApiConfig.baseUrl, style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showServerSettings,
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('关于', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
            title: const Text('ReagentX'),
            subtitle: const Text('课题组试剂管理平台'),
            trailing: Text('v1.0.0', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final up = context.read<UpdateProvider>();
            final scaffold = ScaffoldMessenger.of(context);
            if (up.checking) return;

            scaffold.showSnackBar(
              const SnackBar(content: Text('正在检查更新…'), duration: Duration(seconds: 1)),
            );

            final hasUpdate = await up.checkForUpdate();

            if (!mounted) return;

            if (hasUpdate && up.latest != null) {
              _showUpdateDialog(up.latest!);
            } else if (up.error != null) {
              scaffold.showSnackBar(
                SnackBar(content: Text('检查失败: ${up.error}')),
              );
            } else {
              scaffold.showSnackBar(
                const SnackBar(content: Text('已是最新版本')),
              );
            }
          },
          icon: const Icon(Icons.system_update_outlined, size: 18),
          label: const Text('检查更新'),
        ),
      ],
    );
  }

  void _showServerSettings() {
    final urlCtrl = TextEditingController(text: ApiConfig.baseUrl);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.dns_outlined, size: 20),
            SizedBox(width: 8),
            Text('服务器地址'),
          ],
        ),
        content: TextField(
          controller: urlCtrl,
          decoration: InputDecoration(
            labelText: 'API 地址',
            hintText: 'https://192.168.x.x:8080',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.link),
            errorText: _urlError,
          ),
          style: const TextStyle(fontSize: 14),
          onChanged: (_) {
            if (_urlError != null) setState(() => _urlError = null);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final url = urlCtrl.text.trim();
              final err = _validateUrl(url);
              if (err != null) {
                setState(() => _urlError = err);
                return;
              }
              await ApiConfig.save(url);
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('服务器地址已更新')),
              );
              setState(() {});
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  String? _validateUrl(String url) {
    if (url.isEmpty) return '地址不能为空';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return '格式不正确，示例：https://192.168.1.100:8080';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return '协议必须是 http 或 https';
    }
    return null;
  }

  void _showUpdateDialog(UpdateInfo upd) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.system_update, size: 20),
            const SizedBox(width: 8),
            Text('发现新版本 ${upd.version}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(upd.releaseNotes),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final up = context.read<UpdateProvider>();
              await up.download('android');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.download, size: 18),
            label: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadMyInquiries() async {
    final auth = context.read<AuthProvider>();
    if (auth.userId == null) return;
    try {
      final resp = await http.get(
        ApiConfig.uri('/api/v1/users/${auth.userId}/my-inquiries'),
      );
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        _myInquiries = (body['inquiries'] as List).cast<Map<String, dynamic>>();
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Widget _buildMyInquiriesSection() {
    if (_myInquiries.isEmpty) return const SizedBox.shrink();
    final active = _myInquiries.where((i) => i['status'] != 'archived').toList();
    final archived = _myInquiries.where((i) => i['status'] == 'archived').toList();
    final list = _showMyArchived ? archived : active;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('我的留言', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (_myInquiries.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _showMyArchived = !_showMyArchived),
                icon: Icon(_showMyArchived ? Icons.send : Icons.archive_outlined, size: 18),
                label: Text(
                  _showMyArchived
                      ? '进行中 (${active.length})'
                      : '已归档 (${archived.length})',
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                _showMyArchived ? '暂无已归档留言' : '暂无进行中的留言',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...list.map((inq) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.send_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(child: Text(inq['item_name'] as String? ?? '',
                        style: Theme.of(context).textTheme.titleSmall)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('我: ${inq['message'] as String? ?? ''}',
                    style: Theme.of(context).textTheme.bodyMedium),
                  if ((inq['reply_text'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.reply, size: 14, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('对方回复: ${inq['reply_text']}',
                                  style: Theme.of(context).textTheme.bodySmall),
                                if ((inq['replied_at'] as String? ?? '').isNotEmpty)
                                  Text(inq['replied_at'],
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _statusChip(inq['status'] as String? ?? ''),
                      const Spacer(),
                      if (inq['status'] == 'accepted' || inq['status'] == 'rejected')
                        OutlinedButton.icon(
                          onPressed: () => _updateMyInquiryStatus(inq['id'] as int, 'archived'),
                          icon: const Icon(Icons.archive_outlined, size: 14),
                          label: const Text('归档', style: TextStyle(fontSize: 12)),
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
            ),
          )),
      ],
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
        if (mounted) {
          context.read<InquiryProvider>().fetchPendingCount(auth.userId);
          setState(() {});
        }
      }
    } catch (_) {}
  }

  Widget _buildInquiriesSection() {
    final pending = _inquiries.where((i) => i['status'] == 'pending').toList();
    final archived = _inquiries.where((i) => i['status'] != 'pending').toList();
    final list = _showArchived ? archived : pending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('留言箱', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (_inquiries.isNotEmpty)
              TextButton.icon(
                onPressed: () => setState(() => _showArchived = !_showArchived),
                icon: Icon(_showArchived ? Icons.inbox : Icons.archive_outlined, size: 18),
                label: Text(_showArchived ? '待处理 (${pending.length})' : '归档 (${archived.length})'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Text(
                _showArchived ? '暂无已归档消息' : '暂无待处理留言',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...list.map((inq) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        inq['status'] == 'archived'
                            ? Icons.archive_outlined
                            : Icons.message_outlined,
                        size: 16,
                        color: inq['status'] == 'archived'
                            ? Colors.grey
                            : Theme.of(context).colorScheme.primary,
                      ),
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
                  if ((inq['reply_text'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.reply, size: 14, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('回复: ${inq['reply_text']}',
                                  style: Theme.of(context).textTheme.bodySmall),
                                if ((inq['replied_at'] as String? ?? '').isNotEmpty)
                                  Text(inq['replied_at'],
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
                              onPressed: () => _replyToInquiry(inq['id'] as int, inq['item_name'] as String? ?? ''),
                              icon: const Icon(Icons.reply, size: 14),
                              label: const Text('回复', style: TextStyle(fontSize: 12)),
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
                      if (inq['status'] == 'accepted' || inq['status'] == 'rejected')
                        OutlinedButton.icon(
                          onPressed: () => _updateInquiryStatus(inq['id'] as int, 'archived'),
                          icon: const Icon(Icons.archive_outlined, size: 14),
                          label: const Text('归档', style: TextStyle(fontSize: 12)),
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
            ),
          )),
      ],
    );
  }

  Widget _statusChip(String status) {
    final (label, color) = switch (status) {
      'archived' => ('已归档', Colors.grey),
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

  Future<void> _replyToInquiry(int id, String itemName) async {
    final textCtrl = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('回复: $itemName'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: '输入回复内容…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textCtrl.text.trim()),
            child: const Text('发送回复'),
          ),
        ],
      ),
    );
    if (reply == null || reply.isEmpty) return;

    try {
      final resp = await http.post(
        ApiConfig.uri('/api/v1/inquiries/$id/reply'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'reply_text': reply}),
      );
      if (resp.statusCode == 200) {
        _loadInquiries();
      }
    } catch (_) {}
  }

  Future<void> _updateMyInquiryStatus(int id, String status) async {
    try {
      await http.patch(
        ApiConfig.uri('/api/v1/inquiries/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );
      _loadMyInquiries();
    } catch (_) {}
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


