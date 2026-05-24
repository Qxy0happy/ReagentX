# ReagentX 后端

Go API 服务 — 试剂闲鱼搜索平台后端。

## 技术栈

- Go 1.21+
- HTTP 框架：Gin
- 数据库：SQLite（`modernc.org/sqlite`，纯 Go 无 cgo）
- 搜索：SQLite FTS5 全文索引
- 别名展开：PubChem REST API

## 快速开始

```bash
# 方式一：一键启动（推荐）
.\start-backend.ps1

# 方式二：手动启动
go run .
# 可选：LISTEN_ADDR=:9090 go run .  自定义端口
```

首次启动自动建库 + 建表，无需额外配置。

### Caddy（推荐）

一行命令启动 HTTPS 反向代理（自动生成自签名证书）：

```bash
# 安装 Caddy https://caddyserver.com/download
# 终端 1：启动 Go 后端
go run .

# 终端 2：启动 Caddy 反向代理
caddy reverse-proxy --from localhost:8080 --to localhost:8081
```

- 开发环境：Caddy 自动管理自签名证书
- Docker：`docker compose up -d` 使用 Caddyfile 配置

## API

### 账号

```
POST /api/v1/register     — 注册（创建课题组 + 教师 + 成员）
POST /api/v1/login        — 登录
```

注册示例：

```bash
curl -X POST http://localhost:8080/api/v1/register \
  -H "Content-Type: application/json" \
  -d '{"teacher_name":"李伟","password":"111","members":["张三","李四"]}'
```

### 搜索

```
GET /api/v1/search?q={keyword}
```

搜索时自动做三件事：

1. **同义词展开**（SearchDict） — 如搜"乙醇"同时查"酒精""无水乙醇"
2. **PubChem 别名** — 名称匹配的化学品的全部中英文别名
3. **FTS5 全文检索** — 对 `search_text` 做 BM25 排序

```bash
curl "http://localhost:8080/api/v1/search?q=EDTA"
```

### 物品

```
POST   /api/v1/items              — 发布物品
DELETE /api/v1/items/:id          — 删除物品
PATCH  /api/v1/items/:id/remaining — 修改剩余量
```

### 课题组

```
GET    /api/v1/groups/suggest?q=     — 搜索课题组建议
GET    /api/v1/groups/:id            — 获取课题组详情 + 成员列表
GET    /api/v1/groups/:id/items      — 课题组所有物品
POST   /api/v1/groups/:id/members    — 添加成员
PUT    /api/v1/groups/:id/members/:userId    — 修改成员名
DELETE /api/v1/groups/:id/members/:userId    — 删除成员
```

### 留言

```
POST   /api/v1/items/:id/inquire         — 对某试剂留言（我想要）
GET    /api/v1/users/:id/inquiries       — 收到的留言（本组物品的留言）
GET    /api/v1/users/:id/my-inquiries    — 我发出的留言
POST   /api/v1/inquiries/:id/reply       — 回复留言（自动设为 accepted）
PATCH  /api/v1/inquiries/:id             — 更新留言状态（rejected/archived）
```

### 用户

```
GET  /api/v1/users/:id/items    — 用户发布的物品
PUT  /api/v1/users/:id/password — 修改密码
```

## 项目结构

```
├── main.go             # 入口 + 路由注册 + 建表迁移
├── handlers/
│   ├── auth.go         # 注册/登录/成员管理/密码修改
│   ├── inquiry.go      # 留言 CRUD + 回复
│   ├── item.go         # 物品 CRUD + PubChem 别名展开
│   ├── search.go       # FTS5 搜索 + 评分排序
│   └── user_items.go   # 用户物品列表
├── dict/
│   ├── dict.go         # 同义词字典（Expand）
│   └── tagger.go       # 语义标签推断
├── expand/
│   └── pubchem.go      # PubChem API 调用
└── models/             # 数据结构定义
```

## 搜索原理

```
用户搜 "EDTA"
  ↓
SearchDict.Expand → ["EDTA"]（字典命中）
  ↓
FTS5 MATCH "EDTA" → 命中 item 的 search_text
  ↓
CREATE ITEM 时：
  1. dict.InferTags("EDTA") → 语义标签推断
  2. PubChem API → 30+ 别名写入 SPU.tags
  3. 拼装 search_text = name + brand + size + group + tags
  ↓
另一用户以 "乙二胺四乙酸" 发布 + CAS 60-00-4
  → CAS 归并到同一 SPU → 继承所有别名 → 双向可搜
```