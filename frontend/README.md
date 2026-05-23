# Reagent-X 前端

Flutter 移动端 — Go 后端配套客户端。

## 技术栈

- Flutter 3.44+ / Dart 3.12+
- 状态管理：Provider
- 路由：GoRouter
- 发布表单：手动输入（拍照预览功能实验性）

## 开发

```bash
flutter run
```

确保后端已在 `localhost:8080` 运行：

```bash
cd ../backend
go run .
```

## 项目结构

```
lib/
├── main.dart                  # 入口
├── app.dart                   # 主页 + 个人页（成员管理/物品管理）
├── providers/
│   ├── auth_provider.dart     # 登录态/会话管理
│   └── camera_provider.dart   # 相机状态
├── screens/
│   ├── login_screen.dart      # 登录/注册
│   ├── home_screen.dart       # 首页 + 搜索
│   ├── search_screen.dart     # 搜索结果
│   ├── publish_screen.dart    # 发布物品
│   └── camera_screen.dart     # 拍照
└── widgets/
    └── photo_preview.dart     # 图片预览组件
```

## 功能

- 教师注册/登录，创建课题组
- 成员登录（同组）
- 发布试剂物品（名称、CAS、品牌、规格、剩余量、照片）
- 搜索试剂（FTS5 + PubChem 别名展开）
- 个人页：查看/增删改成员、修改密码、管理物品、修改剩余量
