package main

/*
PostgreSQL ログ分析ツール

使用方法:
    go run log_analyzer.go /var/log/postgresql/postgresql.log
*/

import (
	"bufio"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

type SlowQuery struct {
	Duration float64
	Line     string
}

type PostgreSQLLogAnalyzer struct {
	LogFile     string
	Errors      []string
	SlowQueries []SlowQuery
	Connections map[string]int
}

func NewPostgreSQLLogAnalyzer(logFile string) *PostgreSQLLogAnalyzer {
	return &PostgreSQLLogAnalyzer{
		LogFile:     logFile,
		Errors:      []string{},
		SlowQueries: []SlowQuery{},
		Connections: make(map[string]int),
	}
}

func (a *PostgreSQLLogAnalyzer) ParseLog() error {
	file, err := os.Open(a.LogFile)
	if err != nil {
		return err
	}
	defer file.Close()

	errorPattern := regexp.MustCompile(`ERROR:|FATAL:|PANIC:`)
	slowQueryPattern := regexp.MustCompile(`duration: (\d+\.?\d*) ms`)
	connectionPattern := regexp.MustCompile(`connection (authorized|received)`)
	userPattern := regexp.MustCompile(`user=(\w+)`)

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()

		// エラー検出
		if errorPattern.MatchString(line) {
			a.Errors = append(a.Errors, line)
		}

		// スロークエリ検出
		if matches := slowQueryPattern.FindStringSubmatch(line); matches != nil {
			duration, _ := strconv.ParseFloat(matches[1], 64)
			if duration > 1000 { // 1秒以上
				a.SlowQueries = append(a.SlowQueries, SlowQuery{
					Duration: duration,
					Line:     line,
				})
			}
		}

		// 接続パターン分析
		if connectionPattern.MatchString(line) {
			if userMatches := userPattern.FindStringSubmatch(line); userMatches != nil {
				a.Connections[userMatches[1]]++
			}
		}
	}

	return scanner.Err()
}

func (a *PostgreSQLLogAnalyzer) AnalyzeErrors() {
	fmt.Println(strings.Repeat("=", 80))
	fmt.Println("エラー分析")
	fmt.Println(strings.Repeat("=", 80))

	errorTypes := make(map[string]int)
	for _, error := range a.Errors {
		lowerError := strings.ToLower(error)
		if strings.Contains(lowerError, "deadlock") {
			errorTypes["Deadlock"]++
		} else if strings.Contains(lowerError, "connection") {
			errorTypes["Connection Error"]++
		} else if strings.Contains(lowerError, "syntax") {
			errorTypes["Syntax Error"]++
		} else if strings.Contains(lowerError, "permission") {
			errorTypes["Permission Denied"]++
		} else {
			errorTypes["Other"]++
		}
	}

	fmt.Printf("\n総エラー数: %d\n", len(a.Errors))
	fmt.Println("\nエラータイプ別集計:")
	for errType, count := range errorTypes {
		fmt.Printf("  %s: %d\n", errType, count)
	}

	if len(a.Errors) > 0 {
		fmt.Println("\n最新のエラー（最大5件）:")
		start := len(a.Errors) - 5
		if start < 0 {
			start = 0
		}
		for _, error := range a.Errors[start:] {
			if len(error) > 200 {
				error = error[:200]
			}
			fmt.Printf("  %s\n", error)
		}
	}
}

func (a *PostgreSQLLogAnalyzer) AnalyzeSlowQueries() {
	fmt.Println("\n" + strings.Repeat("=", 80))
	fmt.Println("スロークエリ分析")
	fmt.Println(strings.Repeat("=", 80))

	if len(a.SlowQueries) == 0 {
		fmt.Println("\nスロークエリは検出されませんでした。")
		return
	}

	fmt.Printf("\nスロークエリ数: %d\n", len(a.SlowQueries))

	// 実行時間でソート
	sort.Slice(a.SlowQueries, func(i, j int) bool {
		return a.SlowQueries[i].Duration > a.SlowQueries[j].Duration
	})

	fmt.Println("\n最も遅いクエリ（TOP 5）:")
	limit := 5
	if len(a.SlowQueries) < limit {
		limit = len(a.SlowQueries)
	}
	for i := 0; i < limit; i++ {
		query := a.SlowQueries[i]
		line := query.Line
		if len(line) > 300 {
			line = line[:300]
		}
		fmt.Printf("\n%d. 実行時間: %.2f ms\n", i+1, query.Duration)
		fmt.Printf("   %s\n", line)
	}
}

func (a *PostgreSQLLogAnalyzer) AnalyzeConnections() {
	fmt.Println("\n" + strings.Repeat("=", 80))
	fmt.Println("接続パターン分析")
	fmt.Println(strings.Repeat("=", 80))

	type userCount struct {
		User  string
		Count int
	}
	var users []userCount
	for user, count := range a.Connections {
		users = append(users, userCount{user, count})
	}
	sort.Slice(users, func(i, j int) bool {
		return users[i].Count > users[j].Count
	})

	fmt.Println("\nユーザー別接続数:")
	for _, uc := range users {
		fmt.Printf("  %s: %d\n", uc.User, uc.Count)
	}
}

func (a *PostgreSQLLogAnalyzer) GenerateReport() error {
	fmt.Println("\n" + strings.Repeat("=", 80))
	fmt.Println("PostgreSQL ログ分析レポート")
	fmt.Printf("分析ファイル: %s\n", a.LogFile)
	fmt.Printf("分析日時: %s\n", time.Now().Format("2006-01-02 15:04:05"))
	fmt.Println(strings.Repeat("=", 80))

	if err := a.ParseLog(); err != nil {
		return err
	}

	a.AnalyzeErrors()
	a.AnalyzeSlowQueries()
	a.AnalyzeConnections()

	// 推奨アクション
	fmt.Println("\n" + strings.Repeat("=", 80))
	fmt.Println("推奨アクション")
	fmt.Println(strings.Repeat("=", 80))

	if len(a.Errors) > 100 {
		fmt.Println("⚠️  エラーが多発しています。アプリケーションまたはDB設定を確認してください。")
	}

	if len(a.SlowQueries) > 50 {
		fmt.Println("⚠️  スロークエリが多数検出されました。インデックス最適化を検討してください。")
	}

	maxConnections := 0
	for _, count := range a.Connections {
		if count > maxConnections {
			maxConnections = count
		}
	}
	if maxConnections > 1000 {
		fmt.Println("⚠️  特定ユーザーの接続数が多い。コネクションプーリングを確認してください。")
	}

	return nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("使用方法: go run log_analyzer.go <log_file>")
		os.Exit(1)
	}

	logFile := os.Args[1]
	analyzer := NewPostgreSQLLogAnalyzer(logFile)

	if err := analyzer.GenerateReport(); err != nil {
		fmt.Fprintf(os.Stderr, "エラー: %v\n", err)
		os.Exit(1)
	}
}
