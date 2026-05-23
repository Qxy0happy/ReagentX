package models

// User 子账号（课题组成员）
type User struct {
	ID        string `json:"id"`         // 主键 UUID
	GroupID   string `json:"group_id"`   // 外键 → Group.ID
	Name      string `json:"name"`       // 成员姓名
	Role      string `json:"role"`       // "teacher" | "member"
	CreatedAt string `json:"created_at"` // 创建时间 ISO8601
}
