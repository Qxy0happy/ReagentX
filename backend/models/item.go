package models

// Item 实物发布帖
type Item struct {
	ID           int64  `json:"id"`            // Item_ID 自增主键
	SKUID        string `json:"sku_id"`        // 外键 → SKU.ID
	OwnerUserID  string `json:"owner_user_id"` // 外键 → User.ID（发布者）
	Location     string `json:"location"`      // 存放位置描述，如 "3号柜A排"
	Remaining    string `json:"remaining"`     // 剩余容量评估："20%", "50%", ">90%"
	Status       string `json:"status"`        // 发布状态："On" / "Off"
	ImagePath    string `json:"image_path"`    // 照片路径（可选）
	SearchText   string `json:"search_text"`   // 冗余字段：合并所有可搜索关键词，供全文查询
}
