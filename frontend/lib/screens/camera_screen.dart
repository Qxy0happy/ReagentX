import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/camera_provider.dart';
import '../widgets/photo_preview.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  String? _capturedPath;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未检测到相机')),
        );
      }
      return;
    }

    final controller = CameraController(cameras.first, ResolutionPreset.high);
    _controller = controller;
    _initializeControllerFuture = controller.initialize();
    setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      setState(() {
        _capturedPath = image.path;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败: $e')),
        );
      }
    }
  }

  void _onConfirm() {
    if (_capturedPath != null) {
      context.read<CameraProvider>().setImagePath(_capturedPath);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 已拍照 → 预览
    if (_capturedPath != null) {
      return PhotoPreview(
        imagePath: _capturedPath!,
        onRetake: () => setState(() => _capturedPath = null),
        onConfirm: _onConfirm,
      );
    }

    // 相机未就绪
    if (_controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('相机')),
        body: const Center(child: Text('无法访问相机')),
      );
    }

    // 相机预览
    return Scaffold(
      appBar: AppBar(title: const Text('拍照')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Stack(
              children: [
                SizedBox.expand(
                  child: _controller!.value.isInitialized
                      ? CameraPreview(_controller!)
                      : const Center(child: Text('相机初始化中...')),
                ),
                // 底部拍照按钮
                Positioned(
                  bottom: 48,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _takePicture,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: const Icon(Icons.camera_alt, size: 36, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else if (snapshot.hasError) {
            return Center(child: Text('相机错误: ${snapshot.error}'));
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}
