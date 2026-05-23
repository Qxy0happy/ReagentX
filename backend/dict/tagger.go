package dict

import "strings"

// tagRules 试剂名称关键字 → 语义标签映射
var tagRules = []struct {
	keyword string
	tag     string
}{
	{keyword: "醇", tag: "醇类"},
	{keyword: "酮", tag: "酮类"},
	{keyword: "醛", tag: "醛类"},
	{keyword: "酯", tag: "酯类"},
	{keyword: "醚", tag: "醚类"},
	{keyword: "酸", tag: "酸类"},
	{keyword: "胺", tag: "胺类"},
	{keyword: "烷", tag: "烷烃"},
	{keyword: "烯", tag: "烯烃"},
	{keyword: "炔", tag: "炔烃"},
	{keyword: "苯", tag: "芳香烃"},
	{keyword: "酚", tag: "酚类"},
	{keyword: "吡啶", tag: "杂环化合物"},
	{keyword: "呋喃", tag: "杂环化合物"},
	{keyword: "噻吩", tag: "杂环化合物"},
	{keyword: "吡咯", tag: "杂环化合物"},
	{keyword: "砜", tag: "砜类"},
	{keyword: "腈", tag: "腈类"},
	{keyword: "肼", tag: "肼类"},
	{keyword: "硅", tag: "有机硅"},
	{keyword: "磷", tag: "有机磷"},
	{keyword: "卤", tag: "卤代烃"},
	{keyword: "氯", tag: "卤代烃"},
	{keyword: "溴", tag: "卤代烃"},
	{keyword: "碘", tag: "卤代烃"},
	{keyword: "氟", tag: "卤代烃"},
	{keyword: "甘油", tag: "多元醇"},
	{keyword: "脲", tag: "脲类"},
	{keyword: "醚", tag: "醚类"},
	{keyword: "酐", tag: "酸酐"},
}

// 已知有机官能团/类别关键词，命中任一即标"有机溶剂"
var organicHints = []string{
	"醇", "酮", "醛", "酯", "醚", "酸", "胺", "烷", "烯", "炔",
	"苯", "酚", "吡啶", "呋喃", "噻吩", "砜", "腈", "肼",
	"甘油", "氯", "溴", "碘", "氟", "酐",
}

// InferTags 根据试剂名称自动推断语义标签
// 返回去重后的标签列表
func InferTags(name string) []string {
	seen := map[string]bool{}
	var tags []string

	lower := strings.ToLower(name)

	for _, rule := range tagRules {
		if strings.Contains(lower, rule.keyword) {
			if !seen[rule.tag] {
				seen[rule.tag] = true
				tags = append(tags, rule.tag)
			}
		}
	}

	// 判断是否为有机溶剂
	for _, hint := range organicHints {
		if strings.Contains(lower, hint) {
			if !seen["有机溶剂"] {
				seen["有机溶剂"] = true
				tags = append(tags, "有机溶剂")
			}
			break
		}
	}

	return tags
}
