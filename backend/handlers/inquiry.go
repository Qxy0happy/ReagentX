package handlers

import (
	"database/sql"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// --- 请求/响应结构 ---

type createInquiryReq struct {
	Message string `json:"message" form:"message"`
}

type InquiryResp struct {
	ID           int64  `json:"id"`
	ItemID       int64  `json:"item_id"`
	ItemName     string `json:"item_name"`
	FromUserID   string `json:"from_user_id"`
	FromUserName string `json:"from_user_name"`
	Message      string `json:"message"`
	ReplyText    string `json:"reply_text"`
	RepliedAt    string `json:"replied_at"`
	Status       string `json:"status"`
	CreatedAt    string `json:"created_at"`
}

// CreateInquiryHandler  POST /api/v1/items/:id/inquire  对某试剂留言（我想要）
func CreateInquiryHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		itemID, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid item id"})
			return
		}

		var req createInquiryReq
		if err := c.ShouldBind(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		fromUserID := c.Query("user_id")
		if fromUserID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "user_id is required"})
			return
		}

		var fromUserName string
		err = db.QueryRow("SELECT name FROM users WHERE id = ?", fromUserID).Scan(&fromUserName)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "user not found"})
			return
		}

		var exists bool
		err = db.QueryRow("SELECT EXISTS(SELECT 1 FROM items WHERE id = ?)", itemID).Scan(&exists)
		if err != nil || !exists {
			c.JSON(http.StatusNotFound, gin.H{"error": "item not found"})
			return
		}

		result, err := db.Exec(
			"INSERT INTO inquiries (item_id, from_user_id, from_user_name, message) VALUES (?, ?, ?, ?)",
			itemID, fromUserID, fromUserName, req.Message,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		inquiryID, _ := result.LastInsertId()
		c.JSON(http.StatusCreated, gin.H{"id": inquiryID, "status": "pending"})
	}
}

// ListInquiriesHandler  GET /api/v1/users/:id/inquiries  收到的留言（本组物品的留言）
func ListInquiriesHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("id")

		var groupID string
		err := db.QueryRow("SELECT group_id FROM users WHERE id = ?", userID).Scan(&groupID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "user not found"})
			return
		}

		rows, err := db.Query(`
			SELECT i.id, i.item_id, sp.name, i.from_user_id, i.from_user_name,
			       i.message, i.reply_text, i.replied_at, i.status, i.created_at
			FROM inquiries i
			JOIN items it ON it.id = i.item_id
			JOIN skus sk ON sk.id = it.sku_id
			JOIN spus sp ON sp.id = sk.spu_id
			WHERE it.owner_user_id IN (
				SELECT id FROM users WHERE group_id = ?
			)
			ORDER BY i.created_at DESC
		`, groupID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		inquiries := make([]InquiryResp, 0)
		for rows.Next() {
			var r InquiryResp
			if err := rows.Scan(&r.ID, &r.ItemID, &r.ItemName, &r.FromUserID,
				&r.FromUserName, &r.Message, &r.ReplyText, &r.RepliedAt,
				&r.Status, &r.CreatedAt); err != nil {
				continue
			}
			inquiries = append(inquiries, r)
		}

		c.JSON(http.StatusOK, gin.H{"inquiries": inquiries})
	}
}

// ListMyInquiriesHandler  GET /api/v1/users/:id/my-inquiries  我发出的留言
func ListMyInquiriesHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("id")

		rows, err := db.Query(`
			SELECT i.id, i.item_id, sp.name, i.from_user_id, i.from_user_name,
			       i.message, i.reply_text, i.replied_at, i.status, i.created_at
			FROM inquiries i
			JOIN items it ON it.id = i.item_id
			JOIN skus sk ON sk.id = it.sku_id
			JOIN spus sp ON sp.id = sk.spu_id
			WHERE i.from_user_id = ?
			ORDER BY i.created_at DESC
		`, userID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		inquiries := make([]InquiryResp, 0)
		for rows.Next() {
			var r InquiryResp
			if err := rows.Scan(&r.ID, &r.ItemID, &r.ItemName, &r.FromUserID,
				&r.FromUserName, &r.Message, &r.ReplyText, &r.RepliedAt,
				&r.Status, &r.CreatedAt); err != nil {
				continue
			}
			inquiries = append(inquiries, r)
		}

		c.JSON(http.StatusOK, gin.H{"inquiries": inquiries})
	}
}

// ReplyInquiryHandler  POST /api/v1/inquiries/:id/reply  回复留言（自动设为 accepted）
func ReplyInquiryHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid inquiry id"})
			return
		}

		var body struct {
			ReplyText string `json:"reply_text"`
		}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
		if body.ReplyText == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "reply_text is required"})
			return
		}

		now := time.Now().UTC().Format("2006-01-02 15:04:05")
		result, err := db.Exec(
			"UPDATE inquiries SET reply_text = ?, replied_at = ?, status = 'accepted' WHERE id = ?",
			body.ReplyText, now, id,
		)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		affected, _ := result.RowsAffected()
		if affected == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "inquiry not found"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"status":     "accepted",
			"reply_text": body.ReplyText,
			"replied_at": now,
		})
	}
}

// UpdateInquiryHandler  PATCH /api/v1/inquiries/:id  更新留言状态（accepted / rejected / archived）
func UpdateInquiryHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, err := strconv.ParseInt(c.Param("id"), 10, 64)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid inquiry id"})
			return
		}

		var body struct {
			Status string `json:"status"`
		}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}

		if body.Status != "accepted" && body.Status != "rejected" && body.Status != "archived" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "status must be accepted, rejected or archived"})
			return
		}

		result, err := db.Exec("UPDATE inquiries SET status = ? WHERE id = ?", body.Status, id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		affected, _ := result.RowsAffected()
		if affected == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "inquiry not found"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"status": body.Status})
	}
}
