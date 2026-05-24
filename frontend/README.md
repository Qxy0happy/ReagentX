# ReagentX 前端

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

确保后端已在 `localhost:8080`（HTTPS）运行：

```bash
# Windows
.\backend\start-backend.ps1

# 或其他方式
cd ../backend
go run .
# 另一终端：caddy reverse-proxy --from localhost:8080 --to localhost:8081
```

## 项目结构

```
lib/
├── main.dart                  # 入口
├── app.dart                   # 主页（底部导航）+ 个人页（登录/成员管理/物品/留言/检查更新）
├── config/
│   └── api_config.dart        # API 基础地址（编译期 dart-define）
├── providers/
│   ├── auth_provider.dart     # 登录态/会话管理
│   ├── camera_provider.dart   # 相机状态
│   ├── inquiry_provider.dart  # 留言未读数 badge
│   └── update_provider.dart   # 检查更新
├── screens/
│   ├── login_screen.dart      # 登录/注册（不再通过路由访问，保留备用）
│   ├── home_screen.dart       # 首页 + 搜索
│   ├── search_screen.dart     # 搜索结果
│   ├── publish_screen.dart    # 发布物品
│   └── camera_screen.dart     # 拍照
└── widgets/
    └── photo_preview.dart     # 图片预览组件
```

## 功能

- **课题负责人注册/登录**：在「我的」页面完成，无需独立登录页
- **成员登录**：同组
- **发布试剂**：名称、CAS、品牌、规格、存放位置、剩余量（多/中/少）、照片
- **搜索试剂**：FTS5 + PubChem 别名展开，支持语义标签
- **留言（我想要）**：对试剂留言，课题负责人可回复
- **我的留言**：查看发出的留言及对方回复
- **个人页**：成员管理、密码修改、物品管理（删除/修改剩余量）、检查更新
- **TODO：Flutter Web** — 目前因 `camera` 插件不支持 Web，需条件导入 + 后端 CORS 后启用
- **编译期后端地址**：`flutter run --dart-define-from-file=config.json`
  - 默认回退到 `https://localhost:8080`（Docker / Caddy HTTPS）
  - 本地调试可设 `{"BASE_URL":"http://localhost:8081"}` 直连 Go
