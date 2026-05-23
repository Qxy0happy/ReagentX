package models

// SKU 流转属性商品
// 逻辑主键：Hash(SPU_ID + Brand + Purity + Size)
type SKU struct {
	ID     string `json:"id"`      // 逻辑主键 Hash(SPU_ID+Brand+Size)
	SPUID  string `json:"spu_id"`  // 关联 SPU
	Brand  string `json:"brand"`  // 品牌/厂商
	Size   string `json:"size"`   // 规格容量，如 "500mL", "2.5L"
}
