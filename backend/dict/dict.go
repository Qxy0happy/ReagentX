package dict

import (
	"strings"
)

// SearchDict 语义标签同义词扩展字典
// 存储化学品名/标签的同义词映射，辅助模糊搜索
type SearchDict struct {
	aliases map[string][]string // 标准名 → 别名列表
}

// NewSearchDict 创建字典并初始化示例条目
func NewSearchDict() *SearchDict {
	d := &SearchDict{aliases: make(map[string][]string)}
	d.initExamples()
	return d
}

// Expand 返回标准名及所有别名（展开后的搜索词列表）
func (d *SearchDict) Expand(keyword string) []string {
	keyword = strings.TrimSpace(strings.ToLower(keyword))
	if keyword == "" {
		return nil
	}
	seen := map[string]bool{keyword: true}
	result := []string{keyword}

	// 正向：关键词命中某个标准名 → 展开所有别名
	for k, aliases := range d.aliases {
		if strings.Contains(strings.ToLower(k), keyword) {
			for _, a := range aliases {
				if !seen[a] {
					seen[a] = true
					result = append(result, a)
				}
			}
		}
		// 反向：关键词命中某个别名 → 补上标准名
		for _, a := range aliases {
			if strings.Contains(strings.ToLower(a), keyword) {
				if !seen[k] {
					seen[k] = true
					result = append(result, k)
				}
				break
			}
		}
	}
	return result
}

func (d *SearchDict) initExamples() {
	d.aliases["乙醇"] = []string{"ethanol", "ethyl alcohol", "酒精", "无水乙醇"}
	d.aliases["甲醇"] = []string{"methanol", "methyl alcohol", "木精"}
	d.aliases["丙酮"] = []string{"acetone", "propanone", "二甲基酮"}
	d.aliases["甲苯"] = []string{"toluene", "methylbenzene", "toluol"}
	d.aliases["硫酸"] = []string{"sulfuric acid", "硫磺酸", "battery acid"}
	// 语义标签同义词
	d.aliases["醇类"] = []string{"alcohol", "hydroxyl", "羟基"}
	d.aliases["有机溶剂"] = []string{"organic solvent", "溶剂"}
	d.aliases["酸类"] = []string{"acid", "酸性"}
	d.aliases["易燃"] = []string{"flammable", "combustible", "可燃"}
	d.aliases["剧毒"] = []string{"toxic", "poisonous", "poison", "有毒"}
}
