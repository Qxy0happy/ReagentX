package handlers

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"reagentx/dict"
	"reagentx/expand"
)

const uploadDir = "uploads"

// CreateItemHandler POST /api/v1/items — 发布（multipart/form-data）
// 字段:
//   name, cas, brand, size, location, remaining (表单)
//   image (文件, 可选)
//   owner_user_id (表单)
// tags 由服务端根据 name 自动生成
func CreateItemHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		name := strings.TrimSpace(c.PostForm("name"))
		if name == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
			return
		}

		ownerUserID := c.PostForm("owner_user_id")
		if ownerUserID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "owner_user_id is required"})
			return
		}

		remaining := c.PostForm("remaining")
		valid := map[string]bool{"多": true, "中": true, "少": true}
		if !valid[remaining] {
			remaining = "多"
		}

		// 处理上传图片
		var imagePath string
		file, header, err := c.Request.FormFile("image")
		if err == nil {
			defer file.Close()
			// 确保 uploads 目录存在
			if err := os.MkdirAll(uploadDir, 0755); err != nil {
				log.Printf("mkdir uploads failed: %v", err)
			} else {
				// 生成唯一文件名
				ext := filepath.Ext(header.Filename)
				savedName := fmt.Sprintf("%s_%s%s", time.Now().Format("20060102150405"), uuid.New().String()[:8], ext)
				savePath := filepath.Join(uploadDir, savedName)
				out, err := os.Create(savePath)
				if err == nil {
					defer out.Close()
					if _, err := io.Copy(out, file); err == nil {
						imagePath = savePath
					}
				}
			}
		}

		// 自动推断 tags
		tags := dict.InferTags(name)
		tagsJSON, _ := json.Marshal(tags)

		tx, err := db.Begin()
		if err != nil {
			log.Printf("begin tx failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
			return
		}
		defer tx.Rollback()

		// 1. 查找或创建 SPU（CAS 相同则自动归并）
		spuID := spuKey(name)
		brand := c.PostForm("brand")
		cas := strings.TrimSpace(c.PostForm("cas"))
		size := c.PostForm("size")
		location := c.PostForm("location")

		// 如果提供了 CAS 号，先按 CAS 查找已有 SPU
		if cas != "" {
			var matchedID string
			err = tx.QueryRow(`SELECT id FROM spus WHERE cas = ?`, cas).Scan(&matchedID)
			if err == nil {
				spuID = matchedID
				// 如果当前名称是英文而现有 SPU 的 en_name 为空，补充之
				if isEnglish(name) {
					tx.Exec(`UPDATE spus SET en_name = ? WHERE id = ? AND en_name = ''`, name, spuID)
				}
				// 如果当前名称是中文而现有 SPU 的 name 为空或不同，追加到 tags 辅助搜索
				if !isEnglish(name) {
					var curName string
					tx.QueryRow(`SELECT name FROM spus WHERE id = ?`, spuID).Scan(&curName)
					if curName != name && curName != "" {
						var curTags string
						tx.QueryRow(`SELECT tags FROM spus WHERE id = ?`, spuID).Scan(&curTags)
						newTags := appendJSONString(curTags, name)
						tx.Exec(`UPDATE spus SET tags = ? WHERE id = ?`, newTags, spuID)
					}
				}
			}
		}

		var existing string
		err = tx.QueryRow(`SELECT id FROM spus WHERE id = ?`, spuID).Scan(&existing)
		if err == sql.ErrNoRows {
			enName := ""
			if isEnglish(name) {
				enName = name
			}
			_, err = tx.Exec(
				`INSERT INTO spus (id, name, en_name, cas, tags) VALUES (?, ?, ?, ?, ?)`,
				spuID, name, enName, cas, string(tagsJSON),
			)
			if err != nil {
				log.Printf("insert spu failed: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
				return
			}
		} else if err != nil {
			log.Printf("query spu failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
			return
		}

		// 2. 查找或创建 SKU
		skuID := skuKey(spuID, brand, size)
		err = tx.QueryRow(`SELECT id FROM skus WHERE id = ?`, skuID).Scan(&existing)
		if err == sql.ErrNoRows {
			_, err = tx.Exec(
				`INSERT INTO skus (id, spu_id, brand, size) VALUES (?, ?, ?, ?)`,
				skuID, spuID, brand, size,
			)
			if err != nil {
				log.Printf("insert sku failed: %v", err)
				c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
				return
			}
		} else if err != nil {
			log.Printf("query sku failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
			return
		}

		// 3. 获取发布者信息
		var userName, groupName, teacher string
		err = db.QueryRow(`
			SELECT u.name, g.name, g.teacher
			FROM users u JOIN groups g ON u.group_id = g.id
			WHERE u.id = ?
		`, ownerUserID).Scan(&userName, &groupName, &teacher)
		if err != nil {
			log.Printf("query user failed: %v", err)
			c.JSON(http.StatusBadRequest, gin.H{"error": "user not found"})
			return
		}

		// 4. PubChem 展开别名并补充到 SPU.tags
		synonyms := expand.PubChemSynonyms(name)
		if len(synonyms) > 0 {
			var curTags []string
			if string(tagsJSON) != "[]" {
				json.Unmarshal(tagsJSON, &curTags)
			}
			for _, s := range synonyms {
				curTags = appendJSONStringArr(curTags, s)
			}
			newTagsJSON, _ := json.Marshal(curTags)
			tx.Exec(`UPDATE spus SET tags = ? WHERE id = ?`, string(newTagsJSON), spuID)
			tagsJSON = newTagsJSON
			tags = curTags
		}

		// 5. 从数据库读取 SPU.tags（PubChem 展开的内容或已有 SPU 的别名）
		var spuTagStr string
		tx.QueryRow(`SELECT tags FROM spus WHERE id = ?`, spuID).Scan(&spuTagStr)
		if spuTagStr != "" && spuTagStr != "[]" {
			var dbTags []string
			json.Unmarshal([]byte(spuTagStr), &dbTags)
			tags = dbTags
		}

		// 6. 拼装 search_text（含别名）
		searchParts := []string{name, cas, brand, size, location, groupName, teacher, userName}
		searchParts = append(searchParts, tags...)
		searchText := strings.Join(searchParts, " ")

		// 5. 创建 Item
		var itemID int64
		err = tx.QueryRow(
			`INSERT INTO items (sku_id, owner_user_id, location, remaining, image_path, search_text, updated_at)
			 VALUES (?, ?, ?, ?, ?, ?, datetime('now')) RETURNING id`,
			skuID, ownerUserID, location, remaining, imagePath, searchText,
		).Scan(&itemID)
		if err != nil {
			log.Printf("insert item failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
			return
		}

		if err := tx.Commit(); err != nil {
			log.Printf("commit failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "create failed"})
			return
		}

		c.JSON(http.StatusCreated, gin.H{
			"id":          itemID,
			"spu_id":      spuID,
			"sku_id":      skuID,
			"search_text": searchText,
			"image_path":  imagePath,
			"tags":        tags,
		})
	}
}

// GetGroupItemsHandler GET /api/v1/groups/:id/items
func GetGroupItemsHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		groupID := c.Param("id")

		rows, err := db.Query(`
			SELECT i.id, i.location, i.remaining, i.status, i.image_path, i.search_text, i.updated_at,
			       sp.name, sp.tags,
			       s.brand, s.size,
			       u.name, u.role
			FROM items i
			JOIN skus s ON i.sku_id = s.id
			JOIN spus sp ON s.spu_id = sp.id
			JOIN users u ON i.owner_user_id = u.id
			WHERE u.group_id = ?
			ORDER BY i.id DESC
		`, groupID)
		if err != nil {
			log.Printf("query group items failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "query failed"})
			return
		}
		defer rows.Close()

		type ItemResult struct {
			ID         int64  `json:"id"`
			Location   string `json:"location"`
			Remaining  string `json:"remaining"`
			Status     string `json:"status"`
			UpdatedAt  string `json:"updated_at"`
			ImagePath  string `json:"image_path"`
			SearchText string `json:"search_text"`
			Name       string `json:"name"`
			Tags       string `json:"tags"`
			Brand      string `json:"brand"`
			Size       string `json:"size"`
			UserName   string `json:"user_name"`
			UserRole   string `json:"user_role"`
		}

		var results []ItemResult
		for rows.Next() {
			var r ItemResult
			if err := rows.Scan(&r.ID, &r.Location, &r.Remaining, &r.Status, &r.ImagePath, &r.SearchText, &r.UpdatedAt,
				&r.Name, &r.Tags, &r.Brand, &r.Size,
				&r.UserName, &r.UserRole); err != nil {
				log.Printf("scan failed: %v", err)
				continue
			}
			results = append(results, r)
		}
		if results == nil {
			results = []ItemResult{}
		}

		c.JSON(http.StatusOK, gin.H{"items": results})
	}
}

// UpdateItemRemainingHandler PATCH /api/v1/items/:id/remaining — 修改剩余量
func UpdateItemRemainingHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		itemID := c.Param("id")

		var req struct {
			Remaining string `json:"remaining" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "remaining is required"})
			return
		}

		valid := map[string]bool{"多": true, "中": true, "少": true}
		if !valid[req.Remaining] {
			c.JSON(http.StatusBadRequest, gin.H{"error": "remaining must be 多/中/少"})
			return
		}

		result, err := db.Exec(`UPDATE items SET remaining = ?, updated_at = datetime('now') WHERE id = ?`, req.Remaining, itemID)
		if err != nil {
			log.Printf("update remaining failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "update failed"})
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"updated": true, "remaining": req.Remaining})
	}
}

// isEnglish 判断字符串是否主要包含英文字母（用于区分中英文名）
func isEnglish(s string) bool {
	for _, r := range s {
		if r > 0x7f {
			return false
		}
	}
	return len(s) > 0
}

// appendJSONStringArr 向字符串切片追加去重元素
func appendJSONStringArr(arr []string, item string) []string {
	for _, v := range arr {
		if v == item {
			return arr
		}
	}
	return append(arr, item)
}

// appendJSONString 向 JSON 字符串数组追加一个去重元素
func appendJSONString(jsonArr, item string) string {
	var arr []string
	if jsonArr != "" && jsonArr != "[]" {
		json.Unmarshal([]byte(jsonArr), &arr)
	}
	for _, v := range arr {
		if v == item {
			return jsonArr
		}
	}
	arr = append(arr, item)
	b, _ := json.Marshal(arr)
	return string(b)
}

// spuKey 生成 SPU 主键 (SHA256 of name)
func spuKey(name string) string {
	h := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(name))))
	return hex.EncodeToString(h[:16])
}

// skuKey 生成 SKU 主键 (SHA256 of SPU_ID+brand+size)
func skuKey(spuID, brand, size string) string {
	raw := fmt.Sprintf("%s|%s|%s", spuID, brand, size)
	h := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(h[:16])
}
