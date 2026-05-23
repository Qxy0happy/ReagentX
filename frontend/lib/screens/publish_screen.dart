import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../config/api_config.dart';
import '../providers/auth_provider.dart';

class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key});

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _casCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String _remaining = '多';
  bool _loading = false;
  File? _imageFile;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _casCtrl.dispose();
    _brandCtrl.dispose();
    _sizeCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, maxWidth: 1024);
    if (picked != null) {
      setState(() => _imageFile = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final userId = auth.userId;
    if (userId == null) return;

    setState(() => _loading = true);
    try {
      final request = http.MultipartRequest(
        'POST',
        ApiConfig.uri('/api/v1/items'),
      );

      request.fields['name'] = _nameCtrl.text.trim();
      request.fields['cas'] = _casCtrl.text.trim();
      request.fields['brand'] = _brandCtrl.text.trim();
      request.fields['size'] = _sizeCtrl.text.trim();
      request.fields['location'] = _locationCtrl.text.trim();
      request.fields['remaining'] = _remaining;
      request.fields['owner_user_id'] = userId;

      if (_imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', _imageFile!.path),
        );
      }

      final streamedResp = await request.send();
      final resp = await http.Response.fromStream(streamedResp);

      if (resp.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('发布成功')),
          );
          context.go('/search');
        }
      } else {
        final body = jsonDecode(resp.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('发布失败: ${body['error'] ?? ''}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('网络错误: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发布试剂')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 当前发布者信息
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 20),
                    const SizedBox(width: 8),
                    Consumer<AuthProvider>(
                      builder: (_, auth, _) => Text(
                        '${auth.groupName} · ${auth.userName}${auth.userRole == 'teacher' ? '（教师）' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 照片区域
            Card(
              child: InkWell(
                onTap: () => _showImageSourceDialog(),
                child: Container(
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  child: _imageFile != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_imageFile!, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, shadows: [
                                  Shadow(blurRadius: 4, color: Colors.black54),
                                ]),
                                onPressed: () => setState(() => _imageFile = null),
                              ),
                            ),
                          ],
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('添加照片', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '试剂名称 *',
                hintText: '如：无水乙醇',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入试剂名称' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _casCtrl,
              decoration: const InputDecoration(
                labelText: 'CAS 号',
                hintText: '如：64-17-5',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(
                labelText: '品牌',
                hintText: '如：国药沪试',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sizeCtrl,
                    decoration: const InputDecoration(
                      labelText: '规格容量',
                      hintText: '如：500mL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _locationCtrl,
                    decoration: const InputDecoration(
                      labelText: '存放位置',
                      hintText: '如：A101-3号柜',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _remaining,
              decoration: const InputDecoration(
                labelText: '剩余容量',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '多', child: Text('多（>90%）')),
                DropdownMenuItem(value: '中', child: Text('中（50%~90%）')),
                DropdownMenuItem(value: '少', child: Text('少（<50%）')),
              ],
              onChanged: (v) => setState(() => _remaining = v!),
            ),
            const SizedBox(height: 12),
            Text(
              '语义标签将由系统根据试剂名称自动生成',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('发布'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('从相册选择'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }
}
