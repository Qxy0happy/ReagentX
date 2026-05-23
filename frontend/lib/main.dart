import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/auth_provider.dart';
import 'providers/camera_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 启动时加载持久化登录态
  final auth = AuthProvider();
  await auth.loadSavedSession();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => CameraProvider()),
      ],
      child: const ReagentXApp(),
    ),
  );
}
