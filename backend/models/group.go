package models

// Group 课题组（主账号）
type Group struct {
	ID          string `json:"id"`           // 主键 UUID
	Name        string `json:"name"`         // 课题组名称
	Teacher     string `json:"teacher"`      // 指导教师，如 "张老师"
	LabLocation string `json:"lab_location"` // 实验室地址
	CreatedAt   string `json:"created_at"`   // 创建时间 ISO8601
}
