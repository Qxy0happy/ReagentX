import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../providers/auth_provider.dart';

/// ---- 登录页 ----
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _teacherCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocus = FocusNode();
  final _userCtrl = TextEditingController();
  final _userFocus = FocusNode();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _showSuggestions = false;
  bool _showUserSuggestions = false;
  List<Map<String, dynamic>> _groupMembers = [];

  @override
  void initState() {
    super.initState();
    _teacherCtrl.addListener(_onTeacherChanged);
    _userCtrl.addListener(_onUserChanged);
    // 首次打开时拉取所有课题组缓存到本地
    context.read<AuthProvider>().fetchAllGroups();
  }

  @override
  void dispose() {
    _teacherCtrl.removeListener(_onTeacherChanged);
    _userCtrl.removeListener(_onUserChanged);
    _teacherCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocus.dispose();
    _userCtrl.dispose();
    _userFocus.dispose();
    super.dispose();
  }

  void _onTeacherChanged() {
    setState(() {
      final q = _teacherCtrl.text.trim().toLowerCase();
      if (q.isEmpty) {
        _showSuggestions = false;
      } else {
        final all = context.read<AuthProvider>().allGroups;
        _showSuggestions = all.any((s) =>
          (s['teacher'] as String? ?? '').toLowerCase().contains(q) ||
          (s['group_name'] as String? ?? '').toLowerCase().contains(q));
      }
    });
  }

  void _onUserChanged() {
    if (!_showUserSuggestions && _groupMembers.isNotEmpty) {
      setState(() => _showUserSuggestions = true);
    }
  }

  List<Widget> _buildSuggestions() {
    if (!_showSuggestions) return [];
    return [
      Consumer<AuthProvider>(
        builder: (_, auth, __) {
          final q = _teacherCtrl.text.trim().toLowerCase();
          final filtered = auth.allGroups.where((s) =>
            (s['teacher'] as String? ?? '').toLowerCase().contains(q) ||
            (s['group_name'] as String? ?? '').toLowerCase().contains(q)
          ).take(5).toList();
          if (filtered.isEmpty) return const SizedBox.shrink();
          return Card(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: filtered.map((s) => ListTile(
                dense: true,
                leading: const Icon(Icons.group, size: 20),
                title: Text(s['teacher'] as String? ?? ''),
                subtitle: Text(s['group_name'] as String? ?? '', style: Theme.of(context).textTheme.bodySmall),
                onTap: () async {
                  _teacherCtrl.text = s['teacher'] as String? ?? '';
                  _teacherCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _teacherCtrl.text.length));
                  final gid = s['group_id'] as String?;
                  setState(() => _showSuggestions = false);
                  // 自动拉取该课题组成员
                  if (gid != null) {
                    try {
                      final resp = await http.get(
                        ApiConfig.uri('/api/v1/groups/$gid'),
                      );
                      if (resp.statusCode == 200) {
                        final body = jsonDecode(resp.body);
                        final members = (body['members'] as List).cast<Map<String, dynamic>>();
                        setState(() { _groupMembers = members; _showUserSuggestions = true; });
                      }
                    } catch (_) {}
                  }
                  _passwordFocus.requestFocus();
                },
              )).toList(),
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildUserSuggestions() {
    if (!_showUserSuggestions || _groupMembers.isEmpty) return [];
    final q = _userCtrl.text.trim().toLowerCase();
    final filtered = _groupMembers.where((m) =>
      (m['name'] as String? ?? '').toLowerCase().contains(q)
    ).take(6).toList();
    if (filtered.isEmpty) return [];
    return [
      Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: filtered.map((m) => ListTile(
            dense: true,
            leading: Icon(
              m['role'] == 'teacher' ? Icons.star : Icons.person,
              size: 20,
              color: m['role'] == 'teacher' ? Colors.amber : null,
            ),
            title: Text(m['name'] as String? ?? ''),
            subtitle: Text(m['role'] == 'teacher' ? '教师' : '成员',
              style: Theme.of(context).textTheme.bodySmall),
            onTap: () {
              _userCtrl.text = m['name'] as String? ?? '';
              _userCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _userCtrl.text.length));
              setState(() => _showUserSuggestions = false);
            },
          )).toList(),
        ),
      ),
    ];
  }

  Future<void> _login() async {
    final teacherName = _teacherCtrl.text.trim();
    final password = _passwordCtrl.text;
    final userName = _userCtrl.text.trim();
    if (teacherName.isEmpty || password.isEmpty || userName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写所有字段')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await context.read<AuthProvider>().login(
        teacherName: teacherName,
        password: password,
        userName: userName,
      );
      if (mounted) context.go('/search');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('ReagentX', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('试剂闲鱼', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey)),
            const SizedBox(height: 48),

            // 指导教师（带自动提示）
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _teacherCtrl,
                  decoration: const InputDecoration(
                    labelText: '指导教师姓名',
                    hintText: '如：张伟',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.school),
                  ),
                  onTapOutside: (_) => setState(() => _showSuggestions = false),
                ),
                ..._buildSuggestions(),
              ],
            ),
            const SizedBox(height: 12),

            // 密码
            TextFormField(
              focusNode: _passwordFocus,
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '你的登录密码',
                hintText: '请输入密码',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 成员姓名（带课题组成员建议）
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _userCtrl,
                  focusNode: _userFocus,
                  onTapOutside: (_) => setState(() => _showUserSuggestions = false),
                  decoration: const InputDecoration(
                    labelText: '成员姓名',
                    hintText: '如：李华',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                ..._buildUserSuggestions(),
              ],
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('登录'),
            ),
            const SizedBox(height: 12),

            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RegisterPage()),
              ),
              child: const Text('没有账号？注册课题组'),
            ),
            const SizedBox(height: 4),
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

/// ---- 注册页 ----
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _teacherCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _memberPwdCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _membersCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureMemberPwd = true;

  @override
  void dispose() {
    _teacherCtrl.dispose();
    _passwordCtrl.dispose();
    _memberPwdCtrl.dispose();
    _locationCtrl.dispose();
    _membersCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final members = _membersCtrl.text
          .split(RegExp(r'[,，]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await context.read<AuthProvider>().register(
        teacherName: _teacherCtrl.text.trim(),
        password: _passwordCtrl.text,
        memberPassword: _memberPwdCtrl.text,
        labLocation: _locationCtrl.text.trim(),
        members: members,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('注册成功，请登录')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('注册失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('注册课题组')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _teacherCtrl,
              decoration: const InputDecoration(
                labelText: '指导教师姓名 *',
                hintText: '如：李伟',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入教师姓名' : null,
            ),
            const SizedBox(height: 12),
            Text('课题组名将自动生成为：${_teacherCtrl.text.trim()}课题组',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '你的登录密码 *',
                hintText: '教师使用此密码登录',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? '请设置密码' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _memberPwdCtrl,
              obscureText: _obscureMemberPwd,
              decoration: InputDecoration(
                labelText: '成员默认密码（可选）',
                hintText: '不填则与教师密码相同',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.group_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureMemberPwd ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureMemberPwd = !_obscureMemberPwd),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _locationCtrl,
              decoration: const InputDecoration(
                labelText: '实验室地址',
                hintText: '如：化学楼A301',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _membersCtrl,
              decoration: const InputDecoration(
                labelText: '成员（可选，逗号分隔）',
                hintText: '如：李华, 王芳',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _register,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('注册'),
            ),
          ],
        ),
      ),
    );
  }
}
