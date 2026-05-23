package handlers

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type memberInfo struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Role string `json:"role"`
}

func passwordHash(pw string) string {
	h := sha256.Sum256([]byte(pw))
	return hex.EncodeToString(h[:])
}

// --- 注册 ---

type RegisterRequest struct {
	TeacherName    string   `json:"teacher_name" binding:"required"`
	Password       string   `json:"password" binding:"required"`     // 教师自己的密码
	MemberPassword string   `json:"member_password"`                 // 可选：成员的默认密码（不传则与教师同密码）
	LabLocation    string   `json:"lab_location"`
	Members        []string `json:"members"`
}

func RegisterHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req RegisterRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request: " + err.Error()})
			return
		}

		teacherName := strings.TrimSpace(req.TeacherName)
		teacherPw := req.Password
		if teacherName == "" || teacherPw == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "teacher name and password are required"})
			return
		}
		memberPw := req.MemberPassword
		if memberPw == "" {
			memberPw = teacherPw // 默认与教师同密码
		}

		groupID := uuid.New().String()
		groupName := teacherName + "课题组"

		tx, err := db.Begin()
		if err != nil {
			log.Printf("begin tx failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "registration failed"})
			return
		}
		defer tx.Rollback()

		_, err = tx.Exec(
			`INSERT INTO groups (id, name, teacher, lab_location) VALUES (?, ?, ?, ?)`,
			groupID, groupName, teacherName, req.LabLocation,
		)
		if err != nil {
			log.Printf("insert group failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "registration failed"})
			return
		}

		// 创建教师账号（带密码 hash）
		teacherID := uuid.New().String()
		_, err = tx.Exec(
			`INSERT INTO users (id, group_id, name, role, password_hash) VALUES (?, ?, ?, 'teacher', ?)`,
			teacherID, groupID, teacherName, passwordHash(teacherPw),
		)
		if err != nil {
			log.Printf("insert teacher failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create teacher"})
			return
		}

		memberHash := passwordHash(memberPw)

		var memberIDs []memberInfo
		for _, name := range req.Members {
			name = strings.TrimSpace(name)
			if name == "" {
				continue
			}
			mid := uuid.New().String()
			_, err = tx.Exec(
				`INSERT INTO users (id, group_id, name, role, password_hash) VALUES (?, ?, ?, 'member', ?)`,
				mid, groupID, name, memberHash,
			)
			if err != nil {
				log.Printf("insert member failed: %v", err)
				continue
			}
			memberIDs = append(memberIDs, memberInfo{ID: mid, Name: name, Role: "member"})
		}

		if err := tx.Commit(); err != nil {
			log.Printf("commit failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "registration failed"})
			return
		}

		c.JSON(http.StatusCreated, gin.H{
			"group_id":     groupID,
			"group_name":   groupName,
			"lab_location": req.LabLocation,
			"teacher":      memberInfo{ID: teacherID, Name: teacherName, Role: "teacher"},
			"members":      memberIDs,
		})
	}
}

// --- 登录（按用户校验密码）---

type LoginRequest struct {
	TeacherName string `json:"teacher_name" binding:"required"`
	UserName    string `json:"user_name" binding:"required"`
	Password    string `json:"password" binding:"required"`
}

func LoginHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		var req LoginRequest
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
			return
		}

		teacherName := strings.TrimSpace(req.TeacherName)
		userName := strings.TrimSpace(req.UserName)

		// 查找用户 + 组信息 + 密码 hash
		var user struct {
			UserID      string
			GroupID     string
			GroupName   string
			LabLocation string
			UserName    string
			Role        string
			Teacher     string
			PasswordHash string
		}

		err := db.QueryRow(`
			SELECT u.id, u.group_id, g.name, g.lab_location, u.name, u.role, g.teacher, u.password_hash
			FROM users u
			JOIN groups g ON u.group_id = g.id
			WHERE g.teacher = ? AND u.name = ?
		`, teacherName, userName).Scan(
			&user.UserID, &user.GroupID, &user.GroupName, &user.LabLocation,
			&user.UserName, &user.Role, &user.Teacher, &user.PasswordHash,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
			return
		}
		if err != nil {
			log.Printf("login query failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "login failed"})
			return
		}

		if passwordHash(req.Password) != user.PasswordHash {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "密码错误"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"user_id":      user.UserID,
			"group_id":     user.GroupID,
			"group_name":   user.GroupName,
			"lab_location": user.LabLocation,
			"user_name":    userName,
			"role":         user.Role,
			"teacher":      user.Teacher,
		})
	}
}

// --- 课题组查询 ---

func GetGroupHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		groupID := c.Param("id")

		var group struct {
			ID          string `json:"id"`
			Name        string `json:"name"`
			Teacher     string `json:"teacher"`
			LabLocation string `json:"lab_location"`
			CreatedAt   string `json:"created_at"`
		}
		err := db.QueryRow(`SELECT id, name, teacher, lab_location, created_at FROM groups WHERE id = ?`, groupID).
			Scan(&group.ID, &group.Name, &group.Teacher, &group.LabLocation, &group.CreatedAt)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "group not found"})
			return
		}
		if err != nil {
			log.Printf("get group failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "query failed"})
			return
		}

		rows, err := db.Query(`SELECT id, name, role FROM users WHERE group_id = ? ORDER BY role, name`, groupID)
		if err != nil {
			log.Printf("get members failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "query failed"})
			return
		}
		defer rows.Close()

		type UserInfo struct {
			ID   string `json:"id"`
			Name string `json:"name"`
			Role string `json:"role"`
		}
		var members []UserInfo
		for rows.Next() {
			var m UserInfo
			if rows.Scan(&m.ID, &m.Name, &m.Role) != nil {
				continue
			}
			members = append(members, m)
		}

		c.JSON(http.StatusOK, gin.H{
			"group":   group,
			"members": members,
		})
	}
}

// --- 添加成员（需密码）---

func AddMemberHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		groupID := c.Param("id")

		var req struct {
			Name     string `json:"name" binding:"required"`
			Password string `json:"password"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
			return
		}

		userID := uuid.New().String()
		var pwHash string
		if req.Password != "" {
			pwHash = passwordHash(req.Password)
		} else {
			// 留空则默认使用教师的密码
			err := db.QueryRow(`SELECT password_hash FROM users WHERE group_id = ? AND role = 'teacher'`, groupID).Scan(&pwHash)
			if err != nil {
				pwHash = passwordHash("123456") // 兜底
			}
		}
		_, err := db.Exec(
			`INSERT INTO users (id, group_id, name, role, password_hash) VALUES (?, ?, ?, 'member', ?)`,
			userID, groupID, strings.TrimSpace(req.Name), pwHash,
		)
		if err != nil {
			log.Printf("add member failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to add member"})
			return
		}

		c.JSON(http.StatusCreated, gin.H{"id": userID, "name": req.Name, "role": "member", "default_as_teacher": true})
	}
}

// --- 修改成员 ---

func UpdateMemberHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")

		var req struct {
			Name string `json:"name" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name is required"})
			return
		}

		name := strings.TrimSpace(req.Name)
		if name == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "name cannot be empty"})
			return
		}

		result, err := db.Exec(`UPDATE users SET name = ? WHERE id = ? AND role = 'member'`, name, userID)
		if err != nil {
			log.Printf("update member failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "update failed"})
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"id": userID, "name": name})
	}
}

// --- 修改密码 ---

func UpdatePasswordHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")

		var req struct {
			OldPassword string `json:"old_password" binding:"required"`
			NewPassword string `json:"new_password" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "old_password and new_password are required"})
			return
		}

		// 验证旧密码
		var storedHash string
		err := db.QueryRow(`SELECT password_hash FROM users WHERE id = ?`, userID).Scan(&storedHash)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
			return
		}
		if err != nil {
			log.Printf("query user password failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed"})
			return
		}
		if passwordHash(req.OldPassword) != storedHash {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "旧密码错误"})
			return
		}

		// 更新新密码
		_, err = db.Exec(`UPDATE users SET password_hash = ? WHERE id = ?`, passwordHash(req.NewPassword), userID)
		if err != nil {
			log.Printf("update password failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"updated": true})
	}
}

// --- 删除成员 ---

func DeleteMemberHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		userID := c.Param("userId")

		result, err := db.Exec(`DELETE FROM users WHERE id = ? AND role = 'member'`, userID)
		if err != nil {
			log.Printf("delete member failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "delete failed"})
			return
		}
		n, _ := result.RowsAffected()
		if n == 0 {
			c.JSON(http.StatusNotFound, gin.H{"error": "member not found"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"deleted": true})
	}
}

// --- 课题组联想 ---

func SuggestGroupsHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		q := strings.TrimSpace(c.Query("q"))

		var rows *sql.Rows
		var err error
		if q == "" {
			rows, err = db.Query(`SELECT id, teacher, name FROM groups ORDER BY teacher LIMIT 50`)
		} else {
			rows, err = db.Query(`
				SELECT id, teacher, name FROM groups
				WHERE teacher LIKE ? OR name LIKE ?
				ORDER BY teacher LIMIT 10
			`, "%"+q+"%", "%"+q+"%")
		}

		if err != nil {
			log.Printf("suggest query failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "query failed"})
			return
		}
		defer rows.Close()

		type Suggestion struct {
			GroupID   string `json:"group_id"`
			Teacher   string `json:"teacher"`
			GroupName string `json:"group_name"`
		}
		var suggestions []Suggestion
		for rows.Next() {
			var s Suggestion
			if rows.Scan(&s.GroupID, &s.Teacher, &s.GroupName) == nil {
				suggestions = append(suggestions, s)
			}
		}
		if suggestions == nil {
			suggestions = []Suggestion{}
		}
		c.JSON(http.StatusOK, gin.H{"suggestions": suggestions})
	}
}
