package main

import (
	"database/sql"
	"log"
	"os"

	"github.com/gin-gonic/gin"
	_ "modernc.org/sqlite"

	"reagentx/dict"
	"reagentx/handlers"
)

func main() {
	// 数据库路径，默认 reagent-x.db
	dbPath := os.Getenv("DB_PATH")
	if dbPath == "" {
		dbPath = "reagentx.db"
	}

	db, err := sql.Open("sqlite", dbPath+"?_pragma=journal_mode(WAL)&_pragma=foreign_keys(ON)")
	if err != nil {
		log.Fatalf("failed to open database: %v", err)
	}
	defer db.Close()

	// 验证连接
	if err := db.Ping(); err != nil {
		log.Fatalf("failed to ping database: %v", err)
	}
	log.Printf("connected to SQLite: %s", dbPath)

	// 自动建表
	if err := runMigrations(db); err != nil {
		log.Fatalf("migration failed: %v", err)
	}
	log.Println("database migrated successfully")

	// 初始化搜索字典（语义标签同义词扩展）
	searchDict := dict.NewSearchDict()

	// Gin 路由
	router := gin.Default()

	// 提供上传文件的静态访问
	router.Static("/uploads", "./uploads")

	api := router.Group("/api/v1")
	{
		// 搜索
		api.GET("/search", handlers.SearchHandler(db, searchDict))
		// 账号
		api.POST("/register", handlers.RegisterHandler(db))
		api.POST("/login", handlers.LoginHandler(db))
		api.GET("/groups/suggest", handlers.SuggestGroupsHandler(db))
		api.GET("/groups/:id", handlers.GetGroupHandler(db))
		api.POST("/groups/:id/members", handlers.AddMemberHandler(db))
		api.PUT("/groups/:id/members/:userId", handlers.UpdateMemberHandler(db))
		api.DELETE("/groups/:id/members/:userId", handlers.DeleteMemberHandler(db))
		api.PUT("/users/:userId/password", handlers.UpdatePasswordHandler(db))
		api.GET("/groups/:id/items", handlers.GetGroupItemsHandler(db))
		api.GET("/users/:id/items", handlers.GetUserItemsHandler(db))
		// 留言
		api.POST("/items/:id/inquire", handlers.CreateInquiryHandler(db))
		api.GET("/users/:id/inquiries", handlers.ListInquiriesHandler(db))
		api.PATCH("/inquiries/:id", handlers.UpdateInquiryHandler(db))

		// 发布
		api.POST("/items", handlers.CreateItemHandler(db))
		api.DELETE("/items/:id", handlers.DeleteItemHandler(db))
		api.PATCH("/items/:id/remaining", handlers.UpdateItemRemainingHandler(db))
		// TODO: 语音识别端点 POST /api/v1/voice-recognize
	}

	addr := ":8080"
	log.Printf("starting server on %s", addr)
	if err := router.Run(addr); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}

func runMigrations(db *sql.DB) error {
	schema := `
	CREATE TABLE IF NOT EXISTS spus (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		en_name TEXT NOT NULL DEFAULT '',
		cas TEXT DEFAULT NULL,
		tags TEXT NOT NULL DEFAULT '[]'
	);

	CREATE TABLE IF NOT EXISTS skus (
		id TEXT PRIMARY KEY,
		spu_id TEXT NOT NULL REFERENCES spus(id) ON DELETE CASCADE,
		brand TEXT NOT NULL DEFAULT '',
		size TEXT NOT NULL DEFAULT ''
	);

	CREATE TABLE IF NOT EXISTS groups (
		id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		teacher TEXT NOT NULL DEFAULT '',
		lab_location TEXT NOT NULL DEFAULT '',
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
		image_path TEXT DEFAULT NULL,
		search_text TEXT NOT NULL DEFAULT ''
	);

	CREATE INDEX IF NOT EXISTS idx_items_search ON items(search_text);

	CREATE TABLE IF NOT EXISTS inquiries (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
		from_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		from_user_name TEXT NOT NULL DEFAULT '',
		message TEXT NOT NULL DEFAULT '',
		status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','rejected')),
		created_at TEXT NOT NULL DEFAULT (datetime('now'))
	);

	CREATE INDEX IF NOT EXISTS idx_inquiries_item ON inquiries(item_id);
	CREATE INDEX IF NOT EXISTS idx_inquiries_sender ON inquiries(from_user_id);
	CREATE INDEX IF NOT EXISTS idx_items_owner ON items(owner_user_id);
	CREATE INDEX IF NOT EXISTS idx_spus_name ON spus(name);
	CREATE INDEX IF NOT EXISTS idx_skus_spu ON skus(spu_id);
	CREATE INDEX IF NOT EXISTS idx_users_group ON users(group_id);

	-- FTS5 全文搜索虚拟表
	CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
		search_text,
		content='items',
		content_rowid='id',
		tokenize='unicode61'
	);

	-- FTS5 同步触发器
	CREATE TRIGGER IF NOT EXISTS items_ai AFTER INSERT ON items BEGIN
		INSERT INTO items_fts(rowid, search_text) VALUES (new.id, new.search_text);
	END;
	CREATE TRIGGER IF NOT EXISTS items_ad AFTER DELETE ON items BEGIN
		INSERT INTO items_fts(items_fts, rowid, search_text) VALUES('delete', old.id, old.search_text);
	END;
	CREATE TRIGGER IF NOT EXISTS items_au AFTER UPDATE ON items BEGIN
		INSERT INTO items_fts(items_fts, rowid, search_text) VALUES('delete', old.id, old.search_text);
		INSERT INTO items_fts(rowid, search_text) VALUES (new.id, new.search_text);
	END;

	-- 重建 FTS 索引（初次创建后填充已有数据，或修复索引）
	INSERT INTO items_fts(items_fts) VALUES('rebuild');
	`
	_, err := db.Exec(schema)
	return err
}
