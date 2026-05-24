# ReagentX 项目记忆

## 技术栈（实际）
- **数据库**：SQLite（`modernc.org/sqlite`，纯 Go 无 cgo）
- **搜索**：SQLite FTS5 全文索引（`items_fts` 虚拟表 + 触发器同步）
- **别名展开**：`backend/expand/pubchem.go` — 发布时调 PubChem API 自动获取化学品别名，存入 SPU.tags 和 search_text
- **CAS 归并**：同一 CAS 号自动归并到同一 SPU，跨中英文名可搜索

## 近期新增功能
- **留言回复**：`POST /api/v1/inquiries/:id/reply`，回复时自动设为 accepted；接收方和发送方均可归档
- **检查更新**：`update.json` 通过 jsDelivr CDN 分发，App 内手动检查
- **登录移至「我的」**：独立登录页路由 `/login` 已删除，登录/注册在个人页内完成
- **UpdatedAt 时间戳**：试剂发布和修改剩余量时记录 `updated_at`，显示在搜索结果中
- **角色名统一**：「教师」→「课题负责人」，余量阈值改为 >67%/33%~67%/<33%

## 已知问题 / 边界情况
- `inquiries` 旧表（v0.1.7 以前）缺少 `reply_text`/`replied_at` 列，迁移通过 ALTER TABLE 补充
- `inquiries` 旧表 CHECK constraint 仅允许 `pending/accepted/rejected` 三种状态，v0.1.8 已重建表移除 CHECK（改为 Go 端校验）
- 已存在的 SPU 新增别名后，历史 Item 的 search_text 不会自动更新（FTS5 rebuild 可修复）
- SQLite `datetime('now')` 返回 UTC 时间，改为 `datetime('now','localtime')` + Go `time.Now()` 保证本地时间正确
- **HTTPS**：后端默认监听 `:8081`（HTTP），通过 Caddy（`Caddyfile`）在 `:8080` 提供 HTTPS。开发环境用 `tls internal` 自签名，生产配域名走 Let's Encrypt
