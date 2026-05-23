package handlers

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"sort"
	"strings"

	"github.com/gin-gonic/gin"

	"reagent-x/dict"
)

// searchResult 搜索结果的中间表示（含原始字段和分数）
type searchResult struct {
	ID         int64
	Location   string
	Remaining  string
	Status     string
	ImagePath  string
	SearchText string
	Brand      string
	Size       string
	Name       string
	EnName     string
	Tags       string
	UserName   string
	UserRole   string
	GroupName  string
	Teacher    string
	Score      int
}

// SearchHandler 处理 GET /api/v1/search?q={keyword}
// 使用语义标签 + 名称 + search_text 多维度匹配，按相关度评分排序
func SearchHandler(db *sql.DB, sd *dict.SearchDict) gin.HandlerFunc {
	return func(c *gin.Context) {
		q := strings.TrimSpace(c.Query("q"))
		if q == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "query param 'q' is required"})
			return
		}

		// 展开同义词作为查询词集合
		terms := sd.Expand(q)
		if len(terms) == 0 {
			terms = []string{q}
		}

		// 构建 FTS5 查询：取所有展开词，用 OR 连接
		var ftsParts []string
		for _, t := range terms {
			// FTS5 支持前缀查询：给每个词加 *
			escaped := strings.ReplaceAll(t, "\"", "\"\"")
			ftsParts = append(ftsParts, fmt.Sprintf("\"%s\"", escaped))
		}
		ftsQuery := strings.Join(ftsParts, " OR ")

		query := `
			SELECT i.id, i.location, i.remaining, i.status, i.image_path, i.search_text,
			       s.brand, s.size,
			       sp.name, sp.en_name, sp.tags,
			       u.name, u.role, g.name, g.teacher
			FROM items_fts f
			JOIN items i ON f.rowid = i.id
			JOIN skus s ON i.sku_id = s.id
			JOIN spus sp ON s.spu_id = sp.id
			JOIN users u ON i.owner_user_id = u.id
			JOIN groups g ON u.group_id = g.id
			WHERE items_fts MATCH ?
			ORDER BY rank
			LIMIT 100
		`

		rows, err := db.Query(query, ftsQuery)
		if err != nil {
			log.Printf("search query failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "search failed"})
			return
		}
		defer rows.Close()

		var results []searchResult
		for rows.Next() {
			var r searchResult
			if err := rows.Scan(&r.ID, &r.Location, &r.Remaining,
				&r.Status, &r.ImagePath, &r.SearchText, &r.Brand, &r.Size,
				&r.Name, &r.EnName, &r.Tags,
				&r.UserName, &r.UserRole, &r.GroupName, &r.Teacher); err != nil {
				log.Printf("scan row failed: %v", err)
				continue
			}
			r.Score = computeScore(r, terms)
			results = append(results, r)
		}

		// 按分数降序排列，同分按 ID 降序（最新优先）
		sort.Slice(results, func(i, j int) bool {
			if results[i].Score != results[j].Score {
				return results[i].Score > results[j].Score
			}
			return results[i].ID > results[j].ID
		})

		// 截取前 50 条
		if len(results) > 50 {
			results = results[:50]
		}

		// 映射为 JSON 输出
		type ResultJSON struct {
			ID         int64  `json:"id"`
			Location   string `json:"location"`
			Remaining  string `json:"remaining"`
			Status     string `json:"status"`
			ImagePath  string `json:"image_path"`
			SearchText string `json:"search_text"`
			Brand      string `json:"brand"`
			Size       string `json:"size"`
			Name       string `json:"name"`
			EnName     string `json:"en_name"`
			Tags       string `json:"tags"`
			UserName   string `json:"user_name"`
			UserRole   string `json:"user_role"`
			GroupName  string `json:"group_name"`
			Teacher    string `json:"teacher"`
			Score      int    `json:"score"`
		}

		out := make([]ResultJSON, len(results))
		for i, r := range results {
			out[i] = ResultJSON{
				ID: r.ID, Location: r.Location, Remaining: r.Remaining,
				Status: r.Status, ImagePath: r.ImagePath, SearchText: r.SearchText,
				Brand: r.Brand, Size: r.Size,
				Name: r.Name, EnName: r.EnName, Tags: r.Tags,
				UserName: r.UserName, UserRole: r.UserRole,
				GroupName: r.GroupName, Teacher: r.Teacher,
				Score: r.Score,
			}
		}

		if out == nil {
			out = []ResultJSON{}
		}

		c.JSON(http.StatusOK, gin.H{"results": out, "query": q})
	}
}

// computeScore 计算一条结果与查询词集合的相关度分数
func computeScore(r searchResult, terms []string) int {
	score := 0
	lowerName := strings.ToLower(r.Name)
	lowerSearch := strings.ToLower(r.SearchText)
	lowerBrand := strings.ToLower(r.Brand)
	lowerSize := strings.ToLower(r.Size)
	lowerTags := strings.ToLower(r.Tags)
	lowerGroup := strings.ToLower(r.GroupName)
	lowerTeacher := strings.ToLower(r.Teacher)
	lowerUser := strings.ToLower(r.UserName)

	for _, t := range terms {
		lowerT := strings.ToLower(t)
		if lowerT == "" {
			continue
		}

		// 名称精确匹配（最高分）
		if lowerName == lowerT {
			score += 100
		} else if strings.Contains(lowerName, lowerT) {
			score += 50
		}

		// 语义标签命中
		if strings.Contains(lowerTags, lowerT) {
			score += 30
		}

		// search_text 全文命中
		if strings.Contains(lowerSearch, lowerT) {
			score += 10
		}

		// 品牌/规格
		if strings.Contains(lowerBrand, lowerT) {
			score += 5
		}
		if strings.Contains(lowerSize, lowerT) {
			score += 5
		}

		// 课题组/教师/用户
		if strings.Contains(lowerGroup, lowerT) {
			score += 5
		}
		if strings.Contains(lowerTeacher, lowerT) {
			score += 5
		}
		if strings.Contains(lowerUser, lowerT) {
			score += 5
		}
	}

	return score
}
