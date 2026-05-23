package models

// SPU 化学品本体
// 主搜索维度为语义标签，CAS 仅为辅助字段
type SPU struct {
	ID     string   `json:"id"`      // 主键：自动生成 hash
	Name   string   `json:"name"`    // 化学品名（主要标识），如 "乙醇"
	EnName string   `json:"en_name"` // 英文名（可选），如 "Ethanol"
	CAS    string   `json:"cas"`     // CAS 号（可选，辅助字段），如 "64-17-5"
	Tags   []string `json:"tags"`    // 语义标签，驱动搜索的核心维度
}
