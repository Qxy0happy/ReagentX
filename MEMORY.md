# Reagent-X 项目记忆

## 技术栈（实际）
- **数据库**：SQLite（`modernc.org/sqlite`，纯 Go 无 cgo）
- **搜索**：SQLite FTS5 全文索引（`items_fts` 虚拟表 + 触发器同步）
- **别名展开**：`backend/expand/pubchem.go` — 发布时调 PubChem API 自动获取化学品别名，存入 SPU.tags 和 search_text
- **CAS 归并**：同一 CAS 号自动归并到同一 SPU，跨中英文名可搜索
- **AGENT.md** 已更新，反映上述内容

## 未解决的问题 / 待改进
- 已存在的 SPU 新增别名后，历史 Item 的 search_text 不会自动更新（FTS5 rebuild 可修复）
- 无管理员面板、无审计日志
