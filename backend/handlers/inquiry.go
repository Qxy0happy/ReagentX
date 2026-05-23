package handlers

import (
	"database/sql"
	"net/http"
	"strconv"

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

		// 获取留言者姓名
		var fromUserName string
		err = db.QueryRow("SELECT name FROM users WHERE id = ?", fromUserID).Scan(&fromUserName)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "user not found"})
			return
		}

		// 检查物品是否存在
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

// ListInquiriesHandler  GET /api/v1/users/:userId/inquiries  获取该用户收到的留言（所属课题组的物品留言）
func ListInquiriesHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("id")

		// 查出该用户所在课题组
		var groupID string
		err := db.QueryRow("SELECT group_id FROM users WHERE id = ?", userID).Scan(&groupID)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "user not found"})
			return
		}

		rows, err := db.Query(`
			SELECT i.id, i.item_id, sp.name, i.from_user_id, i.from_user_name,
			       i.message, i.status, i.created_at
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
				&r.FromUserName, &r.Message, &r.Status, &r.CreatedAt); err != nil {
				continue
			}
			inquiries = append(inquiries, r)
		}

		c.JSON(http.StatusOK, gin.H{"inquiries": inquiries})
	}
}

// UpdateInquiryHandler  PATCH /api/v1/inquiries/:id  更新留言状态（accepted / rejected）
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

		if body.Status != "accepted" && body.Status != "rejected" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "status must be accepted or rejected"})
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
