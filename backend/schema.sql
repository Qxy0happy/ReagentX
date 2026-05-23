-- ReagentX Schema (SQLite)
-- 语义标签为核心搜索维度，CAS 仅为辅助字段

CREATE TABLE IF NOT EXISTS spus (
    id TEXT PRIMARY KEY,                   -- 自动生成 hash
    name TEXT NOT NULL,                    -- 化学品名（主要标识）
    en_name TEXT NOT NULL DEFAULT '',      -- 英文名（可选）
    cas TEXT DEFAULT NULL,                 -- CAS 号（可选，辅助）
    tags TEXT NOT NULL DEFAULT '[]'        -- 语义标签 JSON 数组，如 ["醇类","有机溶剂","易燃"]
);

CREATE TABLE IF NOT EXISTS skus (
    id TEXT PRIMARY KEY,                   -- Hash(SPU_ID+Brand+Size)
    spu_id TEXT NOT NULL REFERENCES spus(id) ON DELETE CASCADE,
    brand TEXT NOT NULL DEFAULT '',
    size TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS groups (
    id TEXT PRIMARY KEY,                   -- UUID
    name TEXT NOT NULL,                    -- 课题组名称
    teacher TEXT NOT NULL DEFAULT '',      -- 指导教师
    lab_location TEXT NOT NULL DEFAULT '', -- 实验室地址
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    group_id TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('teacher', 'member')),
    password_hash TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sku_id TEXT NOT NULL REFERENCES skus(id) ON DELETE CASCADE,
    owner_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    location TEXT NOT NULL DEFAULT '',
    remaining TEXT NOT NULL DEFAULT '多' CHECK (remaining IN ('多', '中', '少')),
    status TEXT NOT NULL DEFAULT 'On' CHECK (status IN ('On', 'Off')),
    image_path TEXT DEFAULT NULL,          -- 照片路径（可选）
    search_text TEXT NOT NULL DEFAULT ''   -- 合并关键词冗余字段（含标签）
);

-- 留言功能（类似闲鱼"我想要"）
CREATE TABLE IF NOT EXISTS inquiries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    from_user_name TEXT NOT NULL DEFAULT '',
    message TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected','archived')),
    reply_text TEXT NOT NULL DEFAULT '',
    replied_at TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_inquiries_item ON inquiries(item_id);
CREATE INDEX IF NOT EXISTS idx_inquiries_sender ON inquiries(from_user_id);

CREATE INDEX IF NOT EXISTS idx_items_search ON items(search_text);
CREATE INDEX IF NOT EXISTS idx_items_owner ON items(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_spus_name ON spus(name);
CREATE INDEX IF NOT EXISTS idx_skus_spu ON skus(spu_id);
CREATE INDEX IF NOT EXISTS idx_users_group ON users(group_id);
