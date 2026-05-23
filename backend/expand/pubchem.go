package expand

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// PubChemSynonyms 调用 PubChem API 查询化学品别名
// 返回去重后的别名列表（含查询词本身）
func PubChemSynonyms(name string) []string {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil
	}

	client := &http.Client{Timeout: 5 * time.Second}

	apiURL := fmt.Sprintf("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/%s/synonyms/JSON",
		url.PathEscape(name))

	resp, err := client.Get(apiURL)
	if err != nil {
		log.Printf("pubchem request failed for %q: %v", name, err)
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		log.Printf("pubchem returned %d for %q", resp.StatusCode, name)
		return nil
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("pubchem read failed: %v", err)
		return nil
	}

	var result struct {
		InformationList struct {
			Information []struct {
				CID      int      `json:"CID"`
				Synonym  []string `json:"Synonym"`
			} `json:"Information"`
		} `json:"InformationList"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		log.Printf("pubchem parse failed: %v", err)
		return nil
	}

	if len(result.InformationList.Information) == 0 {
		return nil
	}

	seen := map[string]bool{}
	var synonyms []string
	for _, s := range result.InformationList.Information[0].Synonym {
		s = strings.TrimSpace(s)
		if s == "" || seen[s] {
			continue
		}
		seen[s] = true
		synonyms = append(synonyms, s)
	}

	// 限制返回数量，避免 search_text 过大
	if len(synonyms) > 30 {
		synonyms = synonyms[:30]
	}

	return synonyms
}
