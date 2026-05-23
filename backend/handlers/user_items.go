package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

// GetUserItemsHandler GET /api/v1/users/:id/items — 获取某个用户发布的物品
func GetUserItemsHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("id")

		rows, err := db.Query(`
			SELECT i.id, i.location, i.remaining, i.status, i.image_path, i.updated_at,
			       sp.name, sp.tags, s.brand, s.size
			FROM items i
			JOIN skus s ON i.sku_id = s.id
			JOIN spus sp ON s.spu_id = sp.id
			WHERE i.owner_user_id = ?
			ORDER BY i.id DESC
		`, userID)
		if err != nil {
			log.Printf("query user items failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "query failed"})
			return
		}
		defer rows.Close()

		type Item struct {
			ID        int64  `json:"id"`
			Location  string `json:"location"`
			Remaining string `json:"remaining"`
			UpdatedAt string `json:"updated_at"`
			Status    string `json:"status"`
			ImagePath string `json:"image_path"`
			Name      string `json:"name"`
			Tags      string `json:"tags"`
			Brand     string `json:"brand"`
			Size      string `json:"size"`
		}

		var items []Item
		for rows.Next() {
			var it Item
			if err := rows.Scan(&it.ID, &it.Location, &it.Remaining, &it.Status, &it.ImagePath, &it.UpdatedAt,
				&it.Name, &it.Tags, &it.Brand, &it.Size); err != nil {
				log.Printf("scan failed: %v", err)
				continue
			}
			items = append(items, it)
		}
		if items == nil {
			items = []Item{}
		}

		c.JSON(http.StatusOK, gin.H{"items": items})
	}
}

// DeleteItemHandler DELETE /api/v1/items/:id — 删除物品（需提供 owner_user_id 验证）
func DeleteItemHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		itemID := c.Param("id")
		ownerUserID := c.Query("owner_user_id")
		if ownerUserID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "owner_user_id query param required"})
			return
		}

		// 验证所有权
		var actualOwner string
		err := db.QueryRow(`SELECT owner_user_id FROM items WHERE id = ?`, itemID).Scan(&actualOwner)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
			return
		}
		if err != nil {
			log.Printf("query item owner failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "delete failed"})
			return
		}
		if actualOwner != ownerUserID {
			c.JSON(http.StatusForbidden, gin.H{"error": "not your item"})
			return
		}

		_, err = db.Exec(`DELETE FROM items WHERE id = ?`, itemID)
		if err != nil {
			log.Printf("delete item failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "delete failed"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"deleted": true})
	}
}
