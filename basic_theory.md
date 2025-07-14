# DB基礎理論編：データベース内部アーキテクチャの理解

## 概要

このドキュメントは、データベースエンジニアリングの根幹となる理論的知識を体系的に学ぶためのガイドです。**「なぜインデックスが効くのか？」「なぜこのクエリが遅いのか？」**といった根本的な疑問に答えるため、データベースの内部動作原理を詳しく解説します。

**なぜ内部アーキテクチャの理解が重要なのか？**
- **問題の根本原因を特定できる**: 表面的な症状ではなく、真の原因を見つけられる
- **最適化の判断ができる**: どの手法が効果的かを理論的に予測できる
- **新技術への応用力**: 新しいDBやツールにも原理を応用できる
- **設計判断の根拠**: アーキテクチャ選択に明確な理由を持てる

---

## Chapter 1: データベース基礎アーキテクチャ

### 1.1 データベースシステムの階層構造

データベースは複数の層で構成される複雑なシステムです。各層の役割を理解することで、パフォーマンス問題の原因を特定しやすくなります。

```
┌─────────────────────────────────────┐
│        アプリケーション層           │
│   (アプリケーションコード)          │
└─────────────────────────────────────┘
                  ↕ SQL/API
┌─────────────────────────────────────┐
│         SQLエンジン層               │
│  ・パーサー                         │
│  ・オプティマイザー                 │
│  ・実行エンジン                     │
└─────────────────────────────────────┘
                  ↕ 内部API
┌─────────────────────────────────────┐
│        ストレージエンジン層         │
│  ・バッファプール                   │
│  ・インデックス管理                 │
│  ・ロック管理                       │
│  ・トランザクション管理             │
└─────────────────────────────────────┘
                  ↕ システムコール
┌─────────────────────────────────────┐
│         ファイルシステム層          │
│  ・データファイル                   │
│  ・ログファイル                     │
│  ・一時ファイル                     │
└─────────────────────────────────────┘
                  ↕ I/O
┌─────────────────────────────────────┐
│          物理ストレージ層           │
│  ・HDD / SSD                        │
│  ・メモリ                           │
│  ・CPU                              │
└─────────────────────────────────────┘
```

**各層の詳細解説：**

1. **SQLエンジン層**: 
   - SQL文の解析・最適化を担当
   - 実行計画の生成と実行
   - MySQLでは独立したレイヤー

2. **ストレージエンジン層**:
   - 実際のデータアクセスを担当
   - InnoDBやMyISAMなどが該当
   - データの物理的配置を管理

3. **ファイルシステム層**:
   - OSレベルでのファイル管理
   - バッファリングやキャッシング
   - I/O最適化

### 1.2 メモリ階層とデータアクセスパターン

**メモリ階層と速度差：**

```
┌─────────────────────────────────────┐
│ CPU レジスタ     < 1ns              │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ L1キャッシュ     1-3ns              │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ L2キャッシュ     3-10ns             │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ L3キャッシュ     10-20ns            │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ メインメモリ     50-100ns           │  ← DBバッファプールはここ
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ SSD             0.1-1ms             │  ← DBファイルはここ
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ HDD             5-20ms              │
└─────────────────────────────────────┘
```

**重要なポイント：**
- メモリアクセスとディスクアクセスには **10,000倍以上** の速度差
- データベースの性能はディスクI/Oをいかに減らすかで決まる
- バッファプール（メモリキャッシュ）の重要性がここにある

**データ局所性の活用：**

```
時間的局所性（Temporal Locality）:
最近アクセスしたデータは再度アクセスされる可能性が高い
→ LRU（Least Recently Used）キャッシュが効果的

空間的局所性（Spatial Locality）:
近接したデータが連続してアクセスされる可能性が高い
→ ページ単位での読み込み、シーケンシャルスキャンが効果的
```

### 1.3 ACID特性の実装メカニズム

**ACID特性の復習：**
- **A**tomicity（原子性）: 全て成功するか全て失敗するか
- **C**onsistency（一貫性）: データの整合性が保たれる
- **I**solation（分離性）: 同時実行されるトランザクションが互いに影響しない
- **D**urability（耐久性）: コミットされたデータは永続化される

**実装メカニズム：**

#### Atomicity（原子性）の実装

```
WAL（Write-Ahead Logging）による実装:

1. トランザクション開始
   ┌─────────────────┐
   │ BEGIN           │
   └─────────────────┘
           ↓
2. 変更前の値をログに記録（UNDO log）
   ┌─────────────────┐
   │ OLD VALUE: 100  │ ← ロールバック用
   └─────────────────┘
           ↓
3. データ変更
   ┌─────────────────┐
   │ NEW VALUE: 200  │
   └─────────────────┘
           ↓
4a. COMMIT: ログをディスクに永続化
4b. ROLLBACK: UNDOログで元に戻す
```

#### Durability（耐久性）の実装

```
ログ先行書き込み（WAL）:

メモリ上のバッファプール    ディスク上のファイル
┌─────────────────┐      ┌─────────────────┐
│ データページ    │      │ データファイル  │
│ (更新済み)      │      │ (未更新)        │
└─────────────────┘      └─────────────────┘
         ↑                        ↑
         │                        │
    更新は後で良い              先にログを書く
         │                        │
         └────────────────────────┘
┌─────────────────┐      ┌─────────────────┐
│                 │      │ WALログファイル │
│                 │      │ (更新記録)      │
└─────────────────┘      └─────────────────┘
```

**WALの利点：**
- コミット時にデータページ全体を書く必要なし（ログのみでOK）
- シーケンシャル書き込みでディスクI/Oが高速
- 障害時の復旧が可能（REDOログによる前進復旧）

---

## Chapter 2: ストレージエンジンの内部構造

### 2.1 B-treeインデックスの仕組み

**なぜB-treeなのか？**

従来のバイナリツリーの問題点：
```
バイナリツリー（各ノード2分岐）:
        50
       /  \
     25    75
    /  \   /  \
   12  37 62  87

深さ: log₂(n) ≈ 20層（100万レコードの場合）
ディスクアクセス: 最大20回のI/O
```

B-treeの改善点：
```
B-tree（各ノード多分岐、例：100分岐）:
[10|20|30|....|90]
 ↓  ↓  ↓       ↓
子ノード群（最大100個）

深さ: log₁₀₀(n) ≈ 3層（100万レコードの場合）
ディスクアクセス: 最大3回のI/O
```

**B-treeの詳細構造：**

```
ルートノード（レベル0）
┌─────────────────────────────────────┐
│ [100|300|500|700]                  │
│  ↓   ↓   ↓   ↓   ↓                 │
└─────────────────────────────────────┘

中間ノード（レベル1）
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│[50|75]       │ │[200|250]     │ │[400|450]     │
│ ↓  ↓   ↓     │ │ ↓   ↓   ↓   │ │ ↓   ↓   ↓   │
└──────────────┘ └──────────────┘ └──────────────┘

リーフノード（レベル2）- 実際のデータへのポインタ
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│[10→行1]      │ │[200→行15]    │ │[400→行28]    │
│[25→行3]      │ │[210→行18]    │ │[420→行31]    │
│[40→行7]      │ │[230→行21]    │ │[440→行35]    │
└───────────────┘ └───────────────┘ └───────────────┘
```

**B-treeの特徴：**
1. **バランス木**: 全てのリーフノードが同じ深さ
2. **高い分岐度**: 1ページ（通常16KB）に多くのキーを格納
3. **順序保持**: リーフノード間はリンクされ、範囲検索が効率的

### 2.2 インデックススキャンvsテーブルスキャン

**なぜインデックスが効くのか？**

テーブルスキャンの場合：
```
SELECT * FROM users WHERE age = 25;

全行を順次チェック:
行1: age=20 → 不一致、次へ
行2: age=35 → 不一致、次へ
行3: age=25 → 一致！
...
行100万: age=45 → 不一致

I/O回数: 全ページ数（例：1万ページ = 1万回のI/O）
計算量: O(n)
```

インデックススキャンの場合：
```
SELECT * FROM users WHERE age = 25;

B-treeインデックスを使用:
1. ルートノードから開始（1回目のI/O）
2. 中間ノードをたどる（2回目のI/O）
3. リーフノードで該当キーを発見（3回目のI/O）
4. データページにアクセス（4回目のI/O）

I/O回数: 3-4回
計算量: O(log n)
```

**範囲検索でのインデックスの威力：**

```
SELECT * FROM orders WHERE order_date BETWEEN '2024-01-01' AND '2024-01-31';

インデックスがある場合:
1. B-treeで '2024-01-01' を検索（log n）
2. リーフレベルで順次スキャン（該当データ分のみ）
3. '2024-01-31' で停止

インデックスがない場合:
全テーブルスキャンで全行をチェック
```

### 2.3 クラスター化インデックスと非クラスター化インデックス

**クラスター化インデックス（Clustered Index）:**

```
主キーの物理的順序 = データの物理的順序

インデックス構造:        実際のデータページ:
┌─────────────┐         ┌─────────────────┐
│ Key: 100    │───────→ │ id=100, データ  │
├─────────────┤         ├─────────────────┤
│ Key: 200    │───────→ │ id=200, データ  │
├─────────────┤         ├─────────────────┤
│ Key: 300    │───────→ │ id=300, データ  │
└─────────────┘         └─────────────────┘
```

**非クラスター化インデックス（Non-Clustered Index）:**

```
インデックスキーの順序 ≠ データの物理的順序

セカンダリインデックス:     実際のデータページ:
┌─────────────────┐      ┌─────────────────┐
│ email + 行ID    │────→ │ id=50, データ   │ ← ランダムアクセス
├─────────────────┤      ├─────────────────┤
│ name + 行ID     │────→ │ id=150, データ  │ ← ランダムアクセス
├─────────────────┤      ├─────────────────┤
│ age + 行ID      │────→ │ id=25, データ   │ ← ランダムアクセス
└─────────────────┘      └─────────────────┘
```

**パフォーマンスの違い：**

```
クラスター化インデックス:
- リーフノード = データページ
- 1回のI/Oでデータ取得完了
- 範囲検索が非常に高速（連続アクセス）

非クラスター化インデックス:
- リーフノード → 主キー → データページ
- 2回のI/Oが必要
- 範囲検索でランダムアクセスが発生
```

### 2.4 実践例：インデックス効果の測定

```sql
-- テストテーブルの作成
CREATE TABLE performance_test (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,  -- クラスター化インデックス
    email VARCHAR(255),
    age INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    data TEXT
);

-- 100万件のテストデータを挿入
DELIMITER //
CREATE PROCEDURE GenerateTestData()
BEGIN
    DECLARE i INT DEFAULT 1;
    WHILE i <= 1000000 DO
        INSERT INTO performance_test (email, age, data) VALUES
        (CONCAT('user', i, '@example.com'), 
         20 + (i % 60),  -- 20-79歳の範囲
         REPEAT('test_data_', 100));  -- 約1KBのデータ
        SET i = i + 1;
        
        -- 10,000件ごとにコミット（メモリ使用量制御）
        IF i % 10000 = 0 THEN
            COMMIT;
        END IF;
    END WHILE;
END //
DELIMITER ;

CALL GenerateTestData();

-- 統計情報を更新
ANALYZE TABLE performance_test;
```

**インデックスなしでのテスト：**

```sql
-- 年齢での検索（インデックスなし）
EXPLAIN FORMAT=JSON
SELECT * FROM performance_test WHERE age = 25;

-- 実行時間の測定
SET @start_time = NOW(6);
SELECT COUNT(*) FROM performance_test WHERE age = 25;
SET @end_time = NOW(6);
SELECT TIMESTAMPDIFF(MICROSECOND, @start_time, @end_time) / 1000 AS execution_time_ms;

-- 結果例:
-- 実行時間: 約2000ms
-- 読み取り行数: 1,000,000行（全テーブルスキャン）
-- I/O: 全データページを読み取り
```

**インデックス作成後のテスト：**

```sql
-- インデックスの作成
CREATE INDEX idx_age ON performance_test(age);

-- 同じクエリを再実行
EXPLAIN FORMAT=JSON
SELECT * FROM performance_test WHERE age = 25;

SET @start_time = NOW(6);
SELECT COUNT(*) FROM performance_test WHERE age = 25;
SET @end_time = NOW(6);
SELECT TIMESTAMPDIFF(MICROSECOND, @start_time, @end_time) / 1000 AS execution_time_ms;

-- 結果例:
-- 実行時間: 約50ms（40倍高速化！）
-- 読み取り行数: 約16,667行（該当データのみ）
-- I/O: インデックスページ + 該当データページのみ
```

**複合インデックスの効果：**

```sql
-- メールアドレスと年齢での検索
SELECT * FROM performance_test 
WHERE email LIKE 'user123%' AND age = 25;

-- 個別インデックス使用（効率悪い）
CREATE INDEX idx_email ON performance_test(email);
-- MySQLは一つのインデックスのみ使用
-- email検索 → 結果を age でフィルタリング

-- 複合インデックス使用（効率良い）
CREATE INDEX idx_email_age ON performance_test(email, age);
-- 一つのインデックスで両方の条件を効率的に処理
```

---

## Chapter 3: トランザクション分離レベルとロック機構

### 3.1 同時実行制御の必要性

**なぜロックが必要なのか？**

ロックなしの場合の問題例：
```
時刻  トランザクションA         トランザクションB
t1    READ balance = 1000      
t2                             READ balance = 1000
t3    UPDATE balance = 1500    
t4                             UPDATE balance = 500
t5    COMMIT                   
t6                             COMMIT

結果: balance = 500（正しくは500であるべき？）
→ トランザクションAの更新が失われた（Lost Update）
```

### 3.2 分離レベルの詳細実装

**READ UNCOMMITTED（レベル0）:**
```
実装: ロックなし
問題: ダーティリード

トランザクションA    トランザクションB
BEGIN                BEGIN
UPDATE x = 100       
                     SELECT x  -- 100を読み取り（未コミット）
ROLLBACK             
                     -- 存在しないデータを読んでしまった
```

**READ COMMITTED（レベル1）:**
```
実装: 読み取り時に共有ロック、即座に解放
問題: 非再現読み取り

トランザクションA    トランザクションB
BEGIN                BEGIN
SELECT x  -- 10      
                     UPDATE x = 20
                     COMMIT
SELECT x  -- 20      
-- 同じトランザクション内で異なる値が読める
```

**REPEATABLE READ（レベル2）:**
```
実装: 読み取り時に共有ロック、トランザクション終了まで保持
問題: ファントムリード

トランザクションA    トランザクションB
BEGIN                BEGIN
SELECT COUNT(*)      
WHERE age > 20       
-- 結果: 100件        
                     INSERT INTO users (age) VALUES (25)
                     COMMIT
SELECT COUNT(*)      
WHERE age > 20       
-- 結果: 101件（新しい行が出現）
```

**SERIALIZABLE（レベル3）:**
```
実装: 範囲ロック、完全な分離
問題: 性能低下

全ての読み取り・書き込み操作で範囲ロックを取得
同時実行性が大幅に低下するが、完全な一貫性を保証
```

### 3.3 MVCCによる実装

**MVCC（Multi-Version Concurrency Control）:**

```
各行に複数のバージョンを保持:

行ID  バージョン  値    作成トランザクション  削除トランザクション
1     v1         100   TX1                  TX3
1     v2         200   TX3                  NULL（最新版）
2     v1         50    TX2                  NULL
```

**MVCCの読み取り動作：**

```sql
-- PostgreSQLでのMVCC実装例

-- 時刻t1: トランザクション100開始
BEGIN;  -- トランザクションID: 100

-- 時刻t2: 他のトランザクション101が更新
-- （別セッションで実行）
BEGIN;  -- トランザクションID: 101
UPDATE accounts SET balance = 2000 WHERE id = 1;
COMMIT;

-- 時刻t3: トランザクション100が読み取り
SELECT balance FROM accounts WHERE id = 1;
-- 結果: 1000（トランザクション100開始時点の値）
-- → トランザクション101の更新は見えない（スナップショット分離）

COMMIT;
```

**MVCCの利点：**
- 読み取り操作が書き込み操作をブロックしない
- 書き込み操作が読み取り操作をブロックしない
- 高い同時実行性を実現

### 3.4 デッドロックの原理と対策

**デッドロック発生の条件：**

```
トランザクションA    トランザクションB
LOCK TABLE1          
                     LOCK TABLE2
REQUEST LOCK TABLE2  
（待機中）           REQUEST LOCK TABLE1
                     （待機中）
                     
→ 相互に待機状態（デッドロック）
```

**実際のSQL例：**

```sql
-- セッション1
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- アカウント1をロック
-- この時点でアカウント2を更新しようとすると...

-- セッション2（同時実行）
BEGIN;
UPDATE accounts SET balance = balance + 50 WHERE id = 2;   -- アカウント2をロック
UPDATE accounts SET balance = balance + 100 WHERE id = 1;  -- 待機（アカウント1のロック待ち）

-- セッション1に戻る
UPDATE accounts SET balance = balance - 50 WHERE id = 2;   -- 待機（アカウント2のロック待ち）
-- → デッドロック発生！
```

**デッドロック対策：**

1. **ロック順序の統一:**
```sql
-- 常にIDの小さい順でロック取得
IF @id1 < @id2 THEN
    UPDATE accounts SET balance = ... WHERE id = @id1;
    UPDATE accounts SET balance = ... WHERE id = @id2;
ELSE
    UPDATE accounts SET balance = ... WHERE id = @id2;
    UPDATE accounts SET balance = ... WHERE id = @id1;
END IF;
```

2. **タイムアウト設定:**
```sql
-- MySQLでのロックタイムアウト設定
SET innodb_lock_wait_timeout = 10;  -- 10秒でタイムアウト
```

3. **デッドロック検出と自動復旧:**
```sql
-- InnoDB は自動的にデッドロックを検出し、
-- 影響の少ないトランザクションを自動ロールバック
```

---

## Chapter 4: ストレージ最適化とI/O理解

### 4.1 ページ構造とデータ配置

**データページの内部構造：**

```
┌─────────────────────────────────────┐ ← 16KB（MySQLのデフォルトページサイズ）
│ ページヘッダー（38バイト）          │
│ ・ページ番号                        │
│ ・ページタイプ                      │
│ ・チェックサム                      │
├─────────────────────────────────────┤
│ システムレコード                    │
│ ・Infimum（最小レコード）           │
│ ・Supremum（最大レコード）          │
├─────────────────────────────────────┤
│ ユーザーレコード                    │
│ ┌─────────────────────────────────┐ │
│ │ Record Header + 実際のデータ    │ │
│ │ ・削除フラグ                    │ │
│ │ ・レコード長                    │ │
│ │ ・次レコードへのポインタ        │ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ 次のレコード...                 │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ 空き領域                            │
├─────────────────────────────────────┤
│ ページディレクトリ                  │
│ ・各レコードグループの先頭位置      │
└─────────────────────────────────────┘
│ ページトレーラー（8バイト）         │
│ ・チェックサム（再度）              │
└─────────────────────────────────────┘
```

**行の物理的配置とフラグメンテーション：**

```
新規作成直後のページ:
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│ R1  │ R2  │ R3  │ R4  │ R5  │ R6  │ R7  │空き│
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

R3とR5を削除後:
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│ R1  │ R2  │削除 │ R4  │削除 │ R6  │ R7  │空き│
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘
                ↑             ↑
            フラグメント   フラグメント

新しいレコード（大サイズ）を挿入:
空き領域はあるが、連続していないため挿入不可
→ ページ分割または領域再構成が必要
```

### 4.2 バッファプールの動作原理

**LRU（Least Recently Used）アルゴリズム：**

```
バッファプール（メモリ上のページキャッシュ）:

最新  ←────────────────────────→  最古
┌─────┬─────┬─────┬─────┬─────┬─────┐
│ P1  │ P3  │ P7  │ P2  │ P5  │ P9  │
└─────┴─────┴─────┴─────┴─────┴─────┘

新しいページP10をアクセス:
1. バッファプールに空きがない場合
2. 最も古いP9を削除（必要に応じてディスクに書き込み）
3. P10を先頭に配置

┌─────┬─────┬─────┬─────┬─────┬─────┐
│ P10 │ P1  │ P3  │ P7  │ P2  │ P5  │
└─────┴─────┴─────┴─────┴─────┴─────┘
```

**バッファプールヒット率の重要性：**

```sql
-- MySQLでのバッファプール効率確認
SHOW ENGINE INNODB STATUS\G

-- 重要な指標:
-- Buffer pool hit rate = (読み取り要求 - 物理読み取り) / 読み取り要求
-- 
-- 例: 99.5%のヒット率の場合
-- 1000回のアクセスのうち5回のみディスクI/O
-- 
-- 90%のヒット率の場合  
-- 1000回のアクセスのうち100回ディスクI/O
-- → 20倍のI/O差！
```

### 4.3 Write-Ahead Logging（WAL）の詳細

**WALの書き込み順序：**

```
1. メモリ上でのトランザクション処理:
   ┌─────────────────┐
   │ バッファプール  │
   │ ページA: 変更済み│ ← まだディスクに書かれていない
   └─────────────────┘

2. WALログの書き込み（fsync）:
   ┌─────────────────┐
   │ WALログファイル │
   │ 「ページAを変更」│ ← 先にログを確実にディスクに書く
   └─────────────────┘

3. COMMITの完了:
   クライアントに成功を通知
   
4. 後でデータページの書き込み:
   ┌─────────────────┐
   │ データファイル  │
   │ ページA: 新値   │ ← 後でゆっくり書く（チェックポイント）
   └─────────────────┘
```

**WALの利点：**
- **順次書き込み**: ログファイルは常に末尾に追記（ランダムアクセスなし）
- **小さなI/O**: データページ全体ではなく、変更差分のみ
- **障害回復**: ログから全ての変更を再実行可能

**チェックポイント処理：**

```
定期的なチェックポイント:
1. メモリ上の「汚い」ページをディスクに書き込み
2. どこまで書き込み完了したかをWALに記録
3. 古いWALログファイルを削除可能に

障害回復時:
1. 最後のチェックポイントから開始
2. WALログを順次再実行（REDOログ）
3. 未コミットの変更を取り消し（UNDOログ）
```

---

## Chapter 5: クエリ最適化とコストベース最適化

### 5.1 クエリオプティマイザの動作原理

**オプティマイザの基本的な処理手順：**

```
1. SQL解析（パース）:
   SELECT u.name, COUNT(o.id)
   FROM users u
   LEFT JOIN orders o ON u.id = o.user_id
   WHERE u.created_at > '2023-01-01'
   GROUP BY u.id, u.name
   
   ↓ 構文解析木に変換

2. 論理最適化:
   - 不要な条件の除去
   - 条件の プッシュダウン
   - JOIN順序の検討
   
3. 物理実行計画の生成:
   各操作について複数の実装方法を検討
   - テーブルスキャン vs インデックススキャン
   - Nested Loop vs Hash Join vs Sort Merge Join
   
4. コスト計算:
   各実行計画のコストを見積もり
   
5. 最適な計画の選択:
   最小コストの実行計画を採用
```

### 5.2 コスト計算の仕組み

**統計情報の収集：**

```sql
-- テーブル統計の確認
SHOW TABLE STATUS LIKE 'users'\G

-- 重要な統計情報:
-- Rows: 推定行数
-- Avg_row_length: 平均行長
-- Data_length: データサイズ
-- Index_length: インデックスサイズ

-- カラム統計の確認
SELECT 
    column_name,
    cardinality,      -- 一意値の推定数
    nullable
FROM information_schema.statistics 
WHERE table_name = 'users';
```

**コスト計算例：**

```sql
-- クエリ例
SELECT * FROM users WHERE age = 25;

-- テーブルスキャンのコスト計算:
-- ページ数 = テーブルサイズ / ページサイズ
-- コスト = ページ数 × ページ読み取りコスト
-- 例: 1000ページ × 1.0 = 1000.0

-- インデックススキャンのコスト計算:
-- インデックス深度コスト = log_b(行数) × ページ読み取りコスト  
-- 例: 3レベル × 1.0 = 3.0
-- 
-- データアクセスコスト = 対象行数 × ランダムアクセスコスト
-- 例: 100行 × 1.5 = 150.0
-- 
-- 総コスト = 3.0 + 150.0 = 153.0

-- 結論: インデックススキャンの方が効率的（153.0 < 1000.0）
```

### 5.3 JOIN アルゴリズムの選択

**Nested Loop Join:**

```
SELECT u.name, o.order_date
FROM users u
JOIN orders o ON u.id = o.user_id;

アルゴリズム:
FOR 各ユーザー行 IN users:
    FOR 各注文行 IN orders:
        IF ユーザー行.id = 注文行.user_id:
            結果に追加

コスト: O(M × N)
適用場面: 小さなテーブル同士、一方のテーブルが非常に小さい場合
```

**Hash Join:**

```
アルゴリズム:
1. 小さいテーブル（users）でハッシュテーブル構築:
   Hash[user_id] = user_data

2. 大きいテーブル（orders）をスキャン:
   FOR 各注文行 IN orders:
       IF Hash[注文行.user_id] EXISTS:
           結果に追加

コスト: O(M + N)
適用場面: 大きなテーブル同士のJOIN、等価結合条件
```

**Sort Merge Join:**

```
アルゴリズム:
1. 両テーブルをJOINキーでソート
   users: id順にソート
   orders: user_id順にソート

2. マージ処理:
   両テーブルを同時にスキャンしながらマッチング

コスト: O(M log M + N log N)
適用場面: 既にソート済み、大量データの範囲結合
```

### 5.4 実行計画の読み方

```sql
-- 実行計画の取得
EXPLAIN FORMAT=JSON
SELECT u.username, COUNT(o.id) as order_count
FROM users u
LEFT JOIN orders o ON u.id = o.user_id
WHERE u.created_at > '2023-01-01'
GROUP BY u.id, u.username
HAVING COUNT(o.id) > 5
ORDER BY order_count DESC
LIMIT 10;
```

**EXPLAINの重要な項目：**

```json
{
  "query_block": {
    "select_id": 1,
    "cost_info": {
      "query_cost": "2547.65"    // 総コスト
    },
    "ordering_operation": {      // ORDER BY処理
      "using_filesort": true,    // ソート処理が必要
      "cost_info": {
        "sort_cost": "127.38"
      },
      "grouping_operation": {    // GROUP BY処理
        "using_temporary_table": true,  // 一時テーブル使用
        "nested_loop": [         // JOIN処理
          {
            "table": {
              "table_name": "u",
              "access_type": "range",     // 範囲スキャン
              "key": "idx_created_at",    // 使用インデックス
              "rows_examined_per_scan": 500,  // 調査行数
              "filtered": "100.00",       // フィルタ率
              "cost_info": {
                "read_cost": "122.41",
                "eval_cost": "50.00",
                "prefix_cost": "172.41"
              }
            }
          },
          {
            "table": {
              "table_name": "o",
              "access_type": "ref",       // インデックス参照
              "key": "fk_user_id",
              "rows_examined_per_scan": 5, // ユーザーあたり平均注文数
              "filtered": "100.00"
            }
          }
        ]
      }
    }
  }
}
```

**パフォーマンス問題の特定ポイント：**

1. **access_type が ALL**: フルテーブルスキャン
2. **rows_examined_per_scan が大きい**: 大量行の調査
3. **using_filesort**: ソート処理でI/O発生
4. **using_temporary**: 一時テーブルでメモリ/ディスク使用

---

## Chapter 6: 実践的な性能分析手法

### 6.1 システム全体のボトルネック特定

**性能問題の階層的アプローチ：**

```
1. システムリソース（OS レベル）
   ├─ CPU使用率: top, htop
   ├─ メモリ使用率: free, vmstat  
   ├─ ディスクI/O: iostat, iotop
   └─ ネットワーク: netstat, ss

2. データベースプロセス
   ├─ 接続数: SHOW PROCESSLIST
   ├─ ロック状況: SHOW ENGINE INNODB STATUS
   ├─ バッファプール: SHOW ENGINE INNODB STATUS
   └─ スロークエリ: slow_query_log

3. アプリケーション
   ├─ 接続プール状況
   ├─ クエリ実行頻度
   └─ トランザクション長さ
```

### 6.2 スロークエリ分析の体系的手法

```bash
# スロークエリログの設定
# my.cnf での設定
[mysqld]
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 0.1    # 100ms以上のクエリをログ
log_queries_not_using_indexes = 1
```

```bash
# スロークエリログの分析
# mysqldumpslow を使った分析
mysqldumpslow -s t -t 10 /var/log/mysql/slow.log

# 出力例:
# Count: 142  Time=5.67s (804s)  Lock=0.00s (0s)  Rows=13.4 (1904)  
# SELECT username, email FROM users WHERE LOWER(email) LIKE '%gmail%'

# 分析ポイント:
# Count: 実行回数（142回）
# Time: 平均実行時間（5.67秒）と総実行時間（804秒）
# Lock: 平均ロック時間
# Rows: 平均行数と総行数
```

### 6.3 統計情報の更新と最適化

```sql
-- 統計情報の現在状況確認
SELECT 
    table_name,
    table_rows,
    avg_row_length,
    data_length,
    index_length,
    (data_length + index_length) / 1024 / 1024 as total_mb
FROM information_schema.tables 
WHERE table_schema = 'your_database'
ORDER BY (data_length + index_length) DESC;

-- 統計情報の更新
ANALYZE TABLE users, orders, products;

-- インデックス統計の確認
SELECT 
    table_name,
    index_name,
    cardinality,      -- 一意値の推定数
    sub_part,
    nullable
FROM information_schema.statistics 
WHERE table_schema = 'your_database'
  AND table_name = 'users'
ORDER BY table_name, seq_in_index;
```

**統計情報更新の重要性：**

```sql
-- 統計情報が古い場合の問題例
-- 実際のデータ: 100万行、age=25 は 1000行（0.1%）
-- 古い統計情報: 10万行、age=25 は 5000行（5%）

EXPLAIN SELECT * FROM users WHERE age = 25;

-- オプティマイザの判断:
-- 古い統計情報 → 5% = 5000行 → インデックス使用
-- 実際のデータ → 0.1% = 1000行 → もっと効率的だった

-- 解決策: 定期的な統計情報更新
-- 大きなデータ変更後は手動実行
```

---

## まとめ：DB内部理解がもたらす価値

### 学習成果の確認

この基礎理論編を完了することで、以下の知識が身につきます：

**1. パフォーマンス問題の根本原因特定:**
- 「なぜこのクエリが遅いのか？」を理論的に説明できる
- インデックス設計の判断根拠を持てる
- ボトルネックの真の原因を特定できる

**2. 最適化手法の選択基準:**
- どの最適化手法が効果的かを予測できる
- トレードオフを理解した上で判断できる
- 新しい技術にも応用できる思考力

**3. システム設計への応用:**
- データベースの特性を活かした設計ができる
- スケーラビリティを考慮した判断ができる
- 運用を意識したアーキテクチャ選択ができる

### 次のステップ

基礎理論を理解したら、各データベース固有の実装に進みましょう：

1. **MySQL編**: InnoDBの詳細とMySQL特有の最適化
2. **PostgreSQL編**: MVCC、拡張機能、JSON処理の実践
3. **Redis編**: メモリ最適化とデータ構造活用
4. **パフォーマンステスト編**: 理論を実測で検証
5. **運用実践編**: 本番環境での実践的スキル

### 継続学習のための参考文献

**基礎理論を深める書籍:**
- 「データベース内部構造」（MySQL/PostgreSQL実装の詳細）
- 「高性能MySQL」（実践的な最適化手法）
- 「PostgreSQL徹底入門」（PostgreSQL固有の高度な機能）

**オンラインリソース:**
- MySQL Internals Manual
- PostgreSQL Developer Documentation  
- Redis Documentation - Memory Optimization

**実践的な学習:**
- MySQL/PostgreSQL のソースコード読解
- パフォーマンステストツールの活用
- 本番環境でのトラブルシューティング経験

---

## Chapter 7: 分散データベースの理論と実装

### 7.1 なぜ分散データベースが必要なのか？

**単一サーバーの限界：**

従来の単一データベースサーバーでは、以下の限界に直面します：

```
単一サーバーの制約:
┌─────────────────────────────────────┐
│ CPU: 物理的なコア数の上限           │
│ メモリ: 単一マシンのメモリ容量上限   │
│ ストレージ: 単一ディスクのI/O限界    │
│ ネットワーク: 単一NICの帯域幅限界    │
│ 可用性: 単一障害点（SPOF）の存在     │
└─────────────────────────────────────┘

データ増加に伴う問題:
・データサイズ: TB → PB級への増大
・同時接続数: 数千 → 数万の同時ユーザー
・地理的分散: グローバル展開での地理的距離
・可用性要求: 99.9% → 99.99%への向上要求
```

**分散データベースが解決する問題：**

1. **スケーラビリティ**: 複数サーバーでの処理能力向上
2. **可用性**: 一部のサーバー障害でもサービス継続
3. **地理的分散**: 各地域での低レイテンシアクセス
4. **災害対策**: 地理的に離れた場所でのデータ保護

### 7.2 CAP理論の理解

**CAP理論とは？**

CAP理論は、分散システムにおいて以下の3つの性質のうち、**最大2つまでしか同時に満たせない**ことを示した定理です：

```
C (Consistency): 一貫性
├─ 全ノードが同じ時点で同じデータを持つ
├─ 読み取り操作は最新の書き込み結果を返す
└─ 例: 銀行口座の残高が全支店で一致

A (Availability): 可用性  
├─ システムが常にリクエストに応答する
├─ 一部のノード障害でもサービス継続
└─ 例: Webサイトが24時間365日アクセス可能

P (Partition tolerance): 分断耐性
├─ ネットワーク分断が発生してもシステムが動作
├─ ノード間の通信失敗に対する耐性
└─ 例: データセンター間の回線切断への対応
```

**なぜ3つ全てを満たせないのか？**

具体例で理解しましょう：

```
ケース1: ネットワーク分断が発生した場合

データセンターA        データセンターB
┌─────────────┐       ┌─────────────┐
│ Node1       │  ××   │ Node2       │
│ Balance=100 │       │ Balance=100 │
└─────────────┘       └─────────────┘
        ↑                      ↑
    ユーザーX              ユーザーY
  「50円引き出し」       「30円預け入れ」

選択肢A: 一貫性を優先（CP）
→ 両ノードとも操作を拒否（可用性を犠牲）
→ "ネットワーク復旧まで待ってください"

選択肢B: 可用性を優先（AP）
→ 各ノードが独立して操作を受付（一貫性を犠牲）
→ Node1: Balance=50, Node2: Balance=130
→ ネットワーク復旧後に矛盾解決が必要
```

**実際のデータベースシステムでの選択：**

```
CP系（一貫性+分断耐性）:
・従来のRDBMS（MySQL、PostgreSQL）
・MongoDB（設定による）
・理由: 金融系など厳密な一貫性が必要

AP系（可用性+分断耐性）:
・Cassandra
・DynamoDB  
・理由: ソーシャルメディアなど可用性重視

CA系（一貫性+可用性）:
・単一データセンター内のシステム
・注意: 分散システムでは実質的に選択不可
・理由: ネットワーク分断は必ず発生しうる
```

**参考リンク：**
- [CAP Theorem - Wikipedia](https://en.wikipedia.org/wiki/CAP_theorem)
- [Brewer's CAP Theorem](http://ksat.me/a-plain-english-introduction-to-cap-theorem)

### 7.3 分散データベースのアーキテクチャパターン

#### 7.3.1 シャーディング（水平分割）

**シャーディングとは？**

大きなテーブルを複数の小さなテーブルに分割し、異なるサーバーに配置する手法です：

```
シャーディング前:
┌─────────────────────────────────────┐
│          usersテーブル              │
│  ・user_id: 1-1000万               │
│  ・データサイズ: 1TB               │
│  ・単一サーバーに集中              │
└─────────────────────────────────────┘

シャーディング後:
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Shard 1         │ │ Shard 2         │ │ Shard 3         │
│ user_id: 1-333万│ │user_id:334-666万│ │user_id:667-1000万│
│ データ: 333GB   │ │ データ: 333GB   │ │ データ: 333GB   │
│ Server A        │ │ Server B        │ │ Server C        │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

**シャーディング方式の種類：**

1. **範囲ベースシャーディング:**
```sql
-- user_idの範囲で分割
Shard 1: user_id BETWEEN 1 AND 333333
Shard 2: user_id BETWEEN 333334 AND 666666  
Shard 3: user_id BETWEEN 666667 AND 1000000

-- メリット: 範囲検索が効率的
SELECT * FROM users WHERE user_id BETWEEN 100000 AND 200000;
-- → Shard 1のみアクセス

-- デメリット: データの偏りが発生しやすい
-- 新規ユーザーは常にShard 3に集中
```

2. **ハッシュベースシャーディング:**
```sql
-- user_idのハッシュ値で分割
shard_id = user_id % 3

-- メリット: データが均等に分散
-- デメリット: 範囲検索で全シャードアクセスが必要
SELECT * FROM users WHERE user_id BETWEEN 100000 AND 200000;
-- → 全Shard（1,2,3）にアクセス必要
```

3. **ディレクトリベースシャーディング:**
```sql
-- 別途マッピングテーブルで管理
CREATE TABLE shard_mapping (
    user_id BIGINT PRIMARY KEY,
    shard_id INT NOT NULL
);

-- メリット: 柔軟なデータ配置
-- デメリット: マッピングテーブルがボトルネック
```

**シャーディングの課題と対策：**

```
課題1: クロスシャードクエリ
問題: 複数シャードにまたがるJOINやGROUP BY
対策: 
・データモデリングでクロスシャードを最小化
・アプリケーションレベルでの集約処理

課題2: シャード再分散
問題: データ増加によるシャード追加時の再配置
対策:
・Consistent Hashingの使用
・段階的なデータ移行

課題3: トランザクション処理
問題: 複数シャードにまたがるACID特性の保証
対策:
・2相コミット（2PC）プロトコル
・最終的整合性の許容
```

#### 7.3.2 レプリケーション

**レプリケーションとは？**

同一のデータを複数のサーバーに複製して保存する技術です。可用性向上とread性能の向上を目的とします。

**マスター・スレーブレプリケーション：**

```
マスター（書き込み専用）
┌─────────────────┐
│ Primary Server  │ ←── 全ての書き込み操作
│ ・INSERT        │
│ ・UPDATE        │      
│ ・DELETE        │
└─────────────────┘
         │ バイナリログ
         ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Slave Server 1  │ │ Slave Server 2  │ │ Slave Server 3  │
│ ・SELECT専用    │ │ ・SELECT専用    │ │ ・SELECT専用    │
│ ・読み取り負荷  │ │ ・読み取り負荷  │ │ ・読み取り負荷  │
│   分散          │ │   分散          │ │   分散          │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

**レプリケーションの動作原理（MySQL例）：**

```
1. マスターでの書き込み処理:
   BEGIN;
   UPDATE users SET balance = 1000 WHERE id = 123;
   COMMIT;

2. バイナリログへの記録:
   マスターサーバーが変更内容をバイナリログファイルに記録
   ファイル: mysql-bin.000001
   内容: "UPDATE users SET balance = 1000 WHERE id = 123"

3. スレーブでの複製処理:
   a) I/Oスレッド: マスターからバイナリログを取得
   b) リレーログに保存: 受信したログを一時保存
   c) SQLスレッド: リレーログを読み取り、同じSQL文を実行

4. 結果:
   マスター: users.id=123.balance = 1000
   スレーブ: users.id=123.balance = 1000（少し遅れて同期）
```

**レプリケーション遅延の問題：**

```
時刻  マスター              スレーブ1            スレーブ2
t1    UPDATE balance=1000   balance=500(古い)    balance=500(古い)
t2    (処理完了)           (同期中...)          (同期中...)  
t3                         balance=1000         balance=500(遅延)
t4                         (同期完了)           balance=1000

問題: 読み取り整合性の欠如
・マスターで更新直後にスレーブから読み取ると古い値
・スレーブ間でも同期タイミングが異なる

対策:
・Read Your Writes整合性: 更新ユーザーはマスターから読み取り
・セッションスティッキー: 同一ユーザーは同一スレーブに接続
・同期レプリケーション: マスターは全スレーブの同期完了を待機
```

**マスター・マスターレプリケーション：**

```
Server A (マスター)      Server B (マスター)
┌─────────────────┐     ┌─────────────────┐
│ 読み書き可能    │ ←→  │ 読み書き可能    │
│ 双方向同期      │     │ 双方向同期      │
└─────────────────┘     └─────────────────┘

利点: 高い可用性（どちらかが停止してもサービス継続）
課題: 競合解決（同一データの同時更新時の衝突処理）
```

**競合解決の例：**

```
時刻  Server A              Server B
t1    UPDATE balance=1000   
t2                          UPDATE balance=800
t3    (同期受信)           (同期受信)
      balance=? (競合)      balance=? (競合)

解決方法:
1. Last Writer Wins: より新しいタイムスタンプを採用
2. Version Vector: バージョン番号で管理
3. Application Level: アプリケーションで業務ルールを適用
```

**参考リンク：**
- [MySQL Replication](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)

### 7.4 分散トランザクション

**分散トランザクションの必要性：**

複数のデータベースサーバーにまたがる操作で、ACID特性を保証する必要がある場合：

```
例: 銀行間送金システム
┌─────────────────┐       ┌─────────────────┐
│ Bank A Database │       │ Bank B Database │
│ Account: 123    │       │ Account: 456    │
│ Balance: 1000   │       │ Balance: 500    │
└─────────────────┘       └─────────────────┘

操作: AからBに300円送金
・Bank A: balance = 1000 - 300 = 700
・Bank B: balance = 500 + 300 = 800

要求: 両方成功または両方失敗（原子性）
```

**2相コミット（Two-Phase Commit）プロトコル：**

```
フェーズ1: 準備フェーズ（Prepare Phase）

コーディネーター              参加者A              参加者B
       │                   ┌─────────┐         ┌─────────┐
       │ ──prepare────────→│         │         │         │
       │                   │ 準備OK? │         │         │
       │ ←─OK──────────────│         │         │         │
       │                                       │         │
       │ ──prepare───────────────────────────→│         │
       │                                       │ 準備OK? │
       │ ←─OK──────────────────────────────────│         │
       │                                       │         │

フェーズ2: コミットフェーズ（Commit Phase）

       │ ──commit─────────→│         │         │         │
       │                   │ 確定実行│         │         │
       │ ←─done────────────│         │         │         │
       │                                       │         │
       │ ──commit────────────────────────────→│         │
       │                                       │ 確定実行│
       │ ←─done────────────────────────────────│         │
       │                                       │         │
```

**2PCの動作詳細：**

```sql
-- フェーズ1: 各データベースで事前チェック
-- Bank A Database:
BEGIN;
UPDATE accounts SET balance = balance - 300 WHERE id = 123;
-- まだCOMMITしない（準備状態で保持）
SELECT 'PREPARED' as status;

-- Bank B Database:
BEGIN;  
UPDATE accounts SET balance = balance + 300 WHERE id = 456;
-- まだCOMMITしない（準備状態で保持）
SELECT 'PREPARED' as status;

-- フェーズ2: 全参加者が準備OKなら一斉COMMIT
-- 一つでも失敗なら全員ROLLBACK
-- Bank A & B:
COMMIT;  -- または ROLLBACK;
```

**2PCの問題点：**

```
問題1: ブロッキング
・フェーズ1で参加者がロックを取得
・コーディネーター障害時は長時間ブロック
・可用性への大きな影響

問題2: 単一障害点
・コーディネーターが停止すると全体が停止
・完全な停止リスク

問題3: ネットワーク分断への脆弱性
・「準備OK」は送信されたが「コミット」が届かない
・参加者は永続的に待機状態

代替案: Sagaパターン
・各ステップで補償操作（補正処理）を定義
・失敗時は補償操作で巻き戻し
・最終的整合性を許容
```

**参考リンク：**
- [Distributed Transactions](https://en.wikipedia.org/wiki/Distributed_transaction)
- [Two-Phase Commit Protocol](https://en.wikipedia.org/wiki/Two-phase_commit_protocol)

---

## Chapter 8: レプリケーションの仕組みと実装

### 8.1 レプリケーションの基本原理

**なぜレプリケーションが必要なのか？**

レプリケーションは、データベースシステムにおいて以下の価値を提供します：

```
1. 可用性向上:
   マスターサーバー障害 → スレーブが自動昇格
   サービス停止時間を最小化

2. 読み取り性能向上:
   読み取り負荷を複数サーバーに分散
   同時接続ユーザー数の増加に対応

3. 災害対策:
   地理的に離れた場所にデータを複製
   自然災害からのデータ保護

4. バックアップ負荷軽減:
   スレーブサーバーでバックアップ実行
   マスターの性能への影響を回避
```

### 8.2 物理レプリケーション vs 論理レプリケーション

**物理レプリケーション（ファイルレベル）：**

```
マスターサーバー              スレーブサーバー
┌─────────────────┐          ┌─────────────────┐
│ データページ    │ ──複製──→│ データページ    │
│ ・Page 1: ABC   │          │ ・Page 1: ABC   │
│ ・Page 2: DEF   │          │ ・Page 2: DEF   │  
│ ・Page 3: GHI   │          │ ・Page 3: GHI   │
└─────────────────┘          └─────────────────┘

特徴:
・ディスクブロック単位での完全な複製
・バイト単位で同一のデータファイル
・高速（ディスク I/O の単純な複製）
・異なるバージョン間では互換性なし
```

**論理レプリケーション（SQLレベル）：**

```
マスターサーバー              スレーブサーバー
┌─────────────────┐          ┌─────────────────┐
│ SQL文実行       │ ──SQL──→ │ SQL文実行       │
│ INSERT INTO ... │          │ INSERT INTO ... │
│ UPDATE SET ...  │          │ UPDATE SET ...  │
│ DELETE FROM ... │          │ DELETE FROM ... │
└─────────────────┘          └─────────────────┘

特徴:
・SQL文やロウレベルの変更を転送
・異なるバージョン、異なるOSでも対応可能
・選択的レプリケーション（特定テーブルのみ）可能
・物理レプリケーションより遅い
```

### 8.3 MySQLレプリケーションの詳細実装

**バイナリログの仕組み：**

MySQLのレプリケーションは、マスターのバイナリログを基盤としています：

```
1. マスターでの処理:
   BEGIN;
   INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com');
   UPDATE orders SET status = 'shipped' WHERE id = 123;
   COMMIT;

2. バイナリログへの記録:
   ファイル: mysql-bin.000001
   位置: 4
   内容: 
   # at 4 
   #240115 10:30:15 server id 1 end_log_pos 123 CRC32 0x12345678 Query
   BEGIN
   # at 123
   #240115 10:30:15 server id 1 end_log_pos 245 CRC32 0x87654321 Query  
   INSERT INTO users (name, email) VALUES ('Alice', 'alice@example.com')
   # at 245
   #240115 10:30:15 server id 1 end_log_pos 367 CRC32 0xabcdef12 Query
   UPDATE orders SET status = 'shipped' WHERE id = 123
   # at 367
   #240115 10:30:15 server id 1 end_log_pos 398 CRC32 0x34567890 Xid = 10
   COMMIT

3. スレーブでの読み取り:
   - I/O Thread: マスターからバイナリログを取得
   - SQL Thread: バイナリログの内容を実行
```

**レプリケーション遅延の測定と対策：**

```sql
-- マスターでの遅延確認
SHOW MASTER STATUS;
-- File: mysql-bin.000001
-- Position: 456789
-- Binlog_Do_DB: 
-- Binlog_Ignore_DB:

-- スレーブでの遅延確認  
SHOW SLAVE STATUS\G
-- Master_Log_File: mysql-bin.000001
-- Read_Master_Log_Pos: 456789    ← マスターから読み取った位置
-- Relay_Log_File: relay-bin.000002
-- Relay_Log_Pos: 320             ← リレーログでの位置
-- Exec_Master_Log_Pos: 456700    ← 実際に実行完了した位置
-- Seconds_Behind_Master: 5       ← 遅延秒数

-- 遅延の原因分析:
-- 1. ネットワーク遅延: Read_Master_Log_Pos の更新が遅い
-- 2. ディスクI/O: リレーログの書き込みが遅い  
-- 3. SQL実行: Exec_Master_Log_Pos の更新が遅い
```

**遅延対策の実装：**

```sql
-- 1. 並列レプリケーション有効化
-- マスター設定
SET GLOBAL binlog_transaction_dependency_tracking = WRITESET;
SET GLOBAL transaction_write_set_extraction = XXHASH64;

-- スレーブ設定  
SET GLOBAL slave_parallel_type = LOGICAL_CLOCK;
SET GLOBAL slave_parallel_workers = 4;  -- 並列ワーカー数
STOP SLAVE SQL_THREAD;
START SLAVE SQL_THREAD;

-- 2. 準同期レプリケーション
-- マスター側プラグイン有効化
INSTALL PLUGIN rpl_semi_sync_master SONAME 'semisync_master.so';
SET GLOBAL rpl_semi_sync_master_enabled = 1;
SET GLOBAL rpl_semi_sync_master_timeout = 1000;  -- 1秒タイムアウト

-- スレーブ側プラグイン有効化
INSTALL PLUGIN rpl_semi_sync_slave SONAME 'semisync_slave.so';
SET GLOBAL rpl_semi_sync_slave_enabled = 1;
STOP SLAVE IO_THREAD;
START SLAVE IO_THREAD;
```

**参考リンク：**
- [MySQL Replication Documentation](https://dev.mysql.com/doc/refman/8.0/en/replication.html)
- [MySQL Semi-synchronous Replication](https://dev.mysql.com/doc/refman/8.0/en/replication-semisync.html)

### 8.4 PostgreSQLストリーミングレプリケーション

**WAL（Write-Ahead Log）ベースのレプリケーション：**

PostgreSQLのストリーミングレプリケーションは、WALレコードをリアルタイムでストリーミングします：

```
マスター（Primary）          スタンバイ（Standby）
┌─────────────────┐         ┌─────────────────┐
│ トランザクション│ ──WAL──→│ WAL受信         │
│ 実行            │         │ ↓               │
│ ↓               │         │ WAL適用         │
│ WAL書き込み     │         │ ↓               │
│ ↓               │         │ データ更新      │
│ データ更新      │         │                 │
└─────────────────┘         └─────────────────┘

特徴:
・ブロックレベルでの高速レプリケーション
・自動フェイルオーバー対応
・読み取り専用クエリ実行可能（Hot Standby）
```

**ストリーミングレプリケーションの設定例：**

```bash
# プライマリサーバー設定（postgresql.conf）
wal_level = replica                    # WALレベル設定
max_wal_senders = 3                   # 同時接続スタンバイ数
wal_keep_size = 1024                  # WAL保持サイズ（MB）
archive_mode = on                     # アーカイブモード有効
archive_command = 'cp %p /archive/%f' # アーカイブコマンド

# 接続許可設定（pg_hba.conf）
# スタンバイサーバーからのレプリケーション接続を許可
host replication replicator 192.168.1.100/32 md5

# レプリケーションユーザー作成
CREATE USER replicator REPLICATION LOGIN ENCRYPTED PASSWORD 'password';
```

```bash
# スタンバイサーバー設定
# ベースバックアップ取得
pg_basebackup -h primary-server -D /var/lib/postgresql/data \
              -U replicator -W -R

# standby.signal ファイル作成（PostgreSQL 12以降）
touch /var/lib/postgresql/data/standby.signal

# postgresql.conf 設定
hot_standby = on                      # 読み取りクエリ許可
primary_conninfo = 'host=primary-server port=5432 user=replicator'
```

**レプリケーション状況の監視：**

```sql
-- プライマリサーバーでの監視
SELECT 
    client_addr,
    client_hostname, 
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication;

-- 結果例:
--  client_addr  | state     | write_lag | flush_lag | replay_lag 
-- 192.168.1.100 | streaming | 00:00:00  | 00:00:00  | 00:00:00.05

-- 遅延の意味:
-- write_lag: WALがスタンバイのOSに到達するまでの時間
-- flush_lag: WALがスタンバイのディスクに書き込まれるまでの時間  
-- replay_lag: WALがスタンバイで適用されるまでの時間
```

**参考リンク：**
- [PostgreSQL Streaming Replication](https://www.postgresql.org/docs/current/warm-standby.html)
- [PostgreSQL High Availability](https://www.postgresql.org/docs/current/different-replication-solutions.html)

### 8.5 自動フェイルオーバーの実装

**フェイルオーバーとは？**

マスターサーバーに障害が発生した際に、スレーブサーバーを自動的にマスターに昇格させる仕組みです：

```
正常時:
┌─────────────────┐    複製    ┌─────────────────┐
│ Master          │ ─────────→ │ Slave           │
│ ・読み書き      │            │ ・読み取り専用  │
│ ・アプリから接続│            │ ・待機状態      │
└─────────────────┘            └─────────────────┘
         ↑                              
    ┌─────────┐                         
    │   App   │                         
    └─────────┘                         

障害発生:
┌─────────────────┐    ×××     ┌─────────────────┐
│ Master (故障)   │ ×××××××××→ │ Slave           │
│                 │            │ ・昇格処理      │
│                 │            │ ・マスターに変更│
└─────────────────┘            └─────────────────┘
                                        ↑
                                ┌─────────┐
                                │   App   │ ← 接続先変更
                                └─────────┘
```

**自動フェイルオーバーの実装要素：**

1. **ヘルスチェック**: マスターの生存監視
2. **昇格処理**: スレーブのマスター昇格
3. **接続切り替え**: アプリケーションの接続先変更
4. **データ整合性**: 失われたデータの処理

**ProxySQL を使った接続管理例：**

```sql
-- ProxySQL設定
-- ホストグループ定義
INSERT INTO mysql_servers(hostgroup_id, hostname, port, weight) VALUES
(0, 'mysql-master', 3306, 1000),   -- 書き込み用グループ
(1, 'mysql-slave1', 3306, 900),    -- 読み取り用グループ  
(1, 'mysql-slave2', 3306, 900);

-- ルール定義
INSERT INTO mysql_query_rules(rule_id, match_pattern, destination_hostgroup) VALUES
(1, '^SELECT.*', 1),  -- SELECTは読み取り用グループ
(2, '^INSERT.*', 0),  -- INSERTは書き込み用グループ
(3, '^UPDATE.*', 0),  -- UPDATEは書き込み用グループ
(4, '^DELETE.*', 0);  -- DELETEは書き込み用グループ

-- 設定反映
LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
SAVE MYSQL QUERY RULES TO DISK;
```

**MHA（Master High Availability）を使った自動フェイルオーバー：**

```bash
# MHA設定ファイル例（/etc/mha/app1.cnf）
[server default]
user=mha
password=mhapassword
ssh_user=root
repl_user=replicator  
repl_password=replpassword
ping_interval=3
shutdown_script="/usr/local/bin/power_manager"
report_script="/usr/local/bin/send_report"

[server1]
hostname=mysql-master
port=3306
candidate_master=1

[server2] 
hostname=mysql-slave1
port=3306
candidate_master=1

[server3]
hostname=mysql-slave2  
port=3306
no_master=1          # マスター候補から除外

# フェイルオーバー実行
masterha_check_repl --conf=/etc/mha/app1.cnf    # 設定チェック
masterha_manager --conf=/etc/mha/app1.cnf       # 監視開始
```

**フェイルオーバー時のデータ損失対策：**

```sql
-- 準同期レプリケーションでの対策
-- マスター側設定
SET GLOBAL rpl_semi_sync_master_enabled = 1;
SET GLOBAL rpl_semi_sync_master_wait_for_slave_count = 1;  -- 最低1台の同期確認
SET GLOBAL rpl_semi_sync_master_timeout = 1000;            -- 1秒でタイムアウト

-- この設定により:
-- 1. COMMITはスレーブの受信確認後に完了
-- 2. 確実にスレーブに同期されたデータのみ確定  
-- 3. フェイルオーバー時のデータ損失を防止
-- 4. ただし、書き込み性能は低下
```

**参考リンク：**
- [MHA for MySQL](https://github.com/yoshinorim/mha4mysql-manager)
- [ProxySQL Documentation](https://proxysql.com/documentation/)

---

## Chapter 9: バックアップ・リカバリの原理と実装

### 9.1 バックアップの基本概念

**なぜバックアップが重要なのか？**

データ損失の原因と対策を理解することで、適切なバックアップ戦略を立てることができます：

```
データ損失の原因:
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ ハードウェア障害│ │ ソフトウェア障害│ │ 人的ミス        │
│ ・ディスク故障  │ │ ・バグによる破損│ │ ・誤削除        │
│ ・メモリ故障    │ │ ・OSクラッシュ  │ │ ・設定ミス      │
│ ・電源障害      │ │ ・DB破損        │ │ ・悪意のある操作│
└─────────────────┘ └─────────────────┘ └─────────────────┘
        ↓                    ↓                    ↓
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐  
│ 自然災害        │ │ セキュリティ    │ │ 論理的破損      │
│ ・地震、火災    │ │ ・マルウェア    │ │ ・アプリケーション│
│ ・洪水、停電    │ │ ・ランサムウェア│ │   バグ          │
│ ・データセンター│ │ ・データ漏洩    │ │ ・データ不整合  │
│   全体停止      │ │                 │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘

対策としてのバックアップ要件:
・Recovery Time Objective (RTO): 復旧目標時間
・Recovery Point Objective (RPO): 復旧目標地点
・3-2-1ルール: 3個のコピー、2つの異なるメディア、1つは遠隔地
```

### 9.2 バックアップ手法の種類と特徴

#### 9.2.1 フルバックアップ

**完全バックアップとは？**

データベース全体を完全にコピーする手法です：

```
フルバックアップの流れ:
┌─────────────────┐         ┌─────────────────┐
│ 本番データベース│ ──複製──→│ バックアップ    │
│ ・全テーブル    │         │ ・全テーブル    │
│ ・全インデックス│         │ ・全インデックス│
│ ・設定情報      │         │ ・設定情報      │
│ サイズ: 100GB   │         │ サイズ: 100GB   │
└─────────────────┘         └─────────────────┘

所要時間: データサイズに比例（例: 100GB = 2時間）
ストレージ: 元データと同等のサイズが必要
復旧: 単一ファイルから完全復旧可能
```

**MySQL でのフルバックアップ実装：**

```bash
#!/bin/bash
# フルバックアップスクリプト

# 設定
DB_HOST="localhost"
DB_USER="backup_user"  
DB_PASS="backup_password"
BACKUP_DIR="/backup/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="full_backup_${DATE}.sql"

# バックアップディレクトリ作成
mkdir -p ${BACKUP_DIR}

# mysqldump でフルバックアップ実行
mysqldump \
  --host=${DB_HOST} \
  --user=${DB_USER} \
  --password=${DB_PASS} \
  --single-transaction \    # InnoDB用の一貫性保証
  --routines \              # ストアドプロシージャも含める
  --triggers \              # トリガーも含める  
  --all-databases \         # 全データベース
  --flush-logs \            # バイナリログを切り替え
  --master-data=2 \         # レプリケーション情報を記録
  --result-file=${BACKUP_DIR}/${BACKUP_FILE}

# 実行結果の確認
if [ $? -eq 0 ]; then
    echo "バックアップ成功: ${BACKUP_FILE}"
    
    # ファイルサイズの記録
    SIZE=$(ls -lh ${BACKUP_DIR}/${BACKUP_FILE} | awk '{print $5}')
    echo "ファイルサイズ: ${SIZE}"
    
    # 圧縮（ストレージ容量削減）
    gzip ${BACKUP_DIR}/${BACKUP_FILE}
    echo "圧縮完了: ${BACKUP_FILE}.gz"
    
else
    echo "バックアップ失敗"
    exit 1
fi

# 古いバックアップファイルの削除（30日より古い）
find ${BACKUP_DIR} -name "full_backup_*.sql.gz" -mtime +30 -delete
```

**重要なオプションの解説：**

```sql
-- --single-transaction の効果
-- バックアップ開始時点のスナップショットを取得
-- バックアップ中に他のトランザクションが実行されても
-- 一貫性のあるデータを取得可能

START TRANSACTION WITH CONSISTENT SNAPSHOT;
-- この時点でのデータの状態を記録
-- 以降の変更は見えない（MVCC機能を利用）

-- --master-data=2 の効果  
-- バックアップファイルの先頭にレプリケーション情報を記録
-- ポイントインタイムリカバリで使用

-- CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000123', MASTER_LOG_POS=456789;
-- この情報があることで、バックアップ時点以降のバイナリログから
-- 差分復旧が可能
```

#### 9.2.2 差分バックアップと増分バックアップ

**差分バックアップ（Differential Backup）：**

```
差分バックアップの概念:
日曜日    月曜日    火曜日    水曜日    木曜日
フル ──→ 差分  ──→ 差分  ──→ 差分  ──→ 差分
(100GB)  (5GB)     (10GB)    (15GB)    (20GB)
  ↑       ↑         ↑         ↑         ↑
 全て   日曜以降  日曜以降  日曜以降  日曜以降
       の変更    の変更    の変更    の変更

復旧手順（木曜日の障害の場合）:
1. 日曜日のフルバックアップを復元
2. 木曜日の差分バックアップを適用

メリット: 復旧手順が簡単（2ステップ）
デメリット: 差分サイズが日々増加
```

**増分バックアップ（Incremental Backup）：**

```
増分バックアップの概念:
日曜日    月曜日    火曜日    水曜日    木曜日
フル ──→ 増分  ──→ 増分  ──→ 増分  ──→ 増分
(100GB)  (5GB)     (5GB)     (5GB)     (5GB)
  ↑       ↑         ↑         ↑         ↑
 全て   日曜以降  月曜以降  火曜以降  水曜以降
       の変更    の変更    の変更    の変更

復旧手順（木曜日の障害の場合）:
1. 日曜日のフルバックアップを復元
2. 月曜日の増分バックアップを適用  
3. 火曜日の増分バックアップを適用
4. 水曜日の増分バックアップを適用
5. 木曜日の増分バックアップを適用

メリット: バックアップサイズが小さく一定
デメリット: 復旧手順が複雑（多ステップ）
```

**MySQL でのバイナリログを利用した増分バックアップ：**

```bash
#!/bin/bash
# 増分バックアップスクリプト（バイナリログ活用）

BACKUP_DIR="/backup/mysql/binlog"
MYSQL_DATA_DIR="/var/lib/mysql"
DATE=$(date +%Y%m%d_%H%M%S)

# 現在のバイナリログファイル名を取得
CURRENT_BINLOG=$(mysql -u backup_user -p'backup_password' -e "SHOW MASTER STATUS\G" | grep "File:" | awk '{print $2}')

# バイナリログをローテーション（新しいログファイルを開始）
mysql -u backup_user -p'backup_password' -e "FLUSH LOGS;"

# 前回バックアップから今回までのバイナリログをコピー
# 実装は前回のログファイル名の記録・管理が必要
for logfile in $(ls ${MYSQL_DATA_DIR}/mysql-bin.* | grep -v ${CURRENT_BINLOG} | grep -v index)
do
    if [ ! -f ${BACKUP_DIR}/$(basename ${logfile}) ]; then
        cp ${logfile} ${BACKUP_DIR}/
        echo "バックアップ完了: $(basename ${logfile})"
    fi
done
```

#### 9.2.3 ポイントインタイムリカバリ

**ポイントインタイムリカバリとは？**

特定の時刻のデータ状態に復旧する機能です：

```
シナリオ例:
09:00 フルバックアップ実行
10:30 重要なデータ更新
11:00 誤ってテーブルを削除 ← 復旧したい時点
12:00 現在

復旧手順:
1. 09:00のフルバックアップを復元
2. 09:00-11:00のバイナリログを適用
3. 10:59:59の状態まで復旧完了
```

**実装例：**

```bash
#!/bin/bash
# ポイントインタイムリカバリスクリプト

TARGET_DATETIME="2024-01-15 10:59:59"
BACKUP_FILE="/backup/mysql/full_backup_20240115_090000.sql.gz"
BINLOG_DIR="/backup/mysql/binlog"

echo "ポイントインタイムリカバリ開始: ${TARGET_DATETIME}"

# 1. フルバックアップから復元
echo "1. フルバックアップから復元中..."
zcat ${BACKUP_FILE} | mysql -u root -p

# 2. バイナリログから差分適用
echo "2. バイナリログから差分適用中..."
mysqlbinlog \
    --stop-datetime="${TARGET_DATETIME}" \
    ${BINLOG_DIR}/mysql-bin.000124 \
    ${BINLOG_DIR}/mysql-bin.000125 \
    | mysql -u root -p

echo "復旧完了: ${TARGET_DATETIME} の状態に復旧しました"

# 3. データ確認
echo "3. データ確認:"
mysql -u root -p -e "
SELECT 
    table_name, 
    table_rows, 
    update_time 
FROM information_schema.tables 
WHERE table_schema NOT IN ('information_schema', 'mysql', 'performance_schema');
"
```

**参考リンク：**
- [MySQL Backup and Recovery](https://dev.mysql.com/doc/refman/8.0/en/backup-and-recovery.html)
- [MySQL Point-in-Time Recovery](https://dev.mysql.com/doc/refman/8.0/en/point-in-time-recovery.html)

### 9.3 PostgreSQLでのバックアップ戦略

**PostgreSQLでの物理バックアップ（pg_basebackup）：**

```bash
#!/bin/bash
# PostgreSQL物理バックアップスクリプト

BACKUP_DIR="/backup/postgresql"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/basebackup_${DATE}"

# ベースバックアップ実行
pg_basebackup \
    --host=localhost \
    --username=backup_user \
    --pgdata=${BACKUP_PATH} \
    --format=tar \           # tar形式で圧縮
    --compress=9 \           # 最大圧縮率
    --checkpoint=fast \      # チェックポイント高速実行
    --wal-method=include \   # WALファイルも含める
    --progress \             # 進捗表示
    --verbose                # 詳細出力

# バックアップサイズ確認
if [ $? -eq 0 ]; then
    SIZE=$(du -sh ${BACKUP_PATH} | cut -f1)
    echo "バックアップ成功: ${BACKUP_PATH} (${SIZE})"
else
    echo "バックアップ失敗"
    exit 1
fi
```

**PostgreSQLでの論理バックアップ（pg_dump）：**

```bash
#!/bin/bash
# PostgreSQL論理バックアップスクリプト

DB_NAME="production_db"
BACKUP_DIR="/backup/postgresql"  
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="logical_backup_${DB_NAME}_${DATE}.sql"

# pg_dump実行
pg_dump \
    --host=localhost \
    --username=backup_user \
    --dbname=${DB_NAME} \
    --format=custom \        # カスタム形式（圧縮・並列復元対応）
    --compress=9 \           # 圧縮レベル
    --no-owner \             # 所有者情報を除外
    --no-privileges \        # 権限情報を除外  
    --verbose \              # 詳細出力
    --file=${BACKUP_DIR}/${BACKUP_FILE}

# スキーマのみのバックアップも作成（高速復旧用）
pg_dump \
    --host=localhost \
    --username=backup_user \
    --dbname=${DB_NAME} \
    --schema-only \          # スキーマのみ
    --file=${BACKUP_DIR}/schema_${DB_NAME}_${DATE}.sql
```

**WALアーカイブの設定：**

```bash
# postgresql.conf での設定
wal_level = replica                    # WALレベル
archive_mode = on                      # アーカイブ有効
archive_command = 'cp %p /backup/postgresql/wal_archive/%f'  # アーカイブコマンド
archive_timeout = 300                  # 5分でアーカイブ強制実行

# WALアーカイブディレクトリ作成
mkdir -p /backup/postgresql/wal_archive
chown postgres:postgres /backup/postgresql/wal_archive
```

**PostgreSQLでのポイントインタイムリカバリ：**

```bash
#!/bin/bash  
# PostgreSQLポイントインタイムリカバリ

TARGET_TIME="2024-01-15 10:59:59"
BACKUP_PATH="/backup/postgresql/basebackup_20240115_090000"
WAL_ARCHIVE="/backup/postgresql/wal_archive"
RECOVERY_PATH="/var/lib/postgresql/recovery"

echo "PostgreSQLポイントインタイムリカバリ開始"

# 1. データディレクトリ初期化
systemctl stop postgresql
rm -rf /var/lib/postgresql/data/*

# 2. ベースバックアップから復元
cd /var/lib/postgresql/data
tar -xf ${BACKUP_PATH}/base.tar
tar -xf ${BACKUP_PATH}/pg_wal.tar -C pg_wal

# 3. recovery.conf作成（PostgreSQL 12以降はpostgresql.confに記述）
cat > postgresql.conf << EOF
# 通常設定
shared_buffers = 256MB
# リカバリ設定  
restore_command = 'cp ${WAL_ARCHIVE}/%f %p'
recovery_target_time = '${TARGET_TIME}'
recovery_target_action = 'promote'
EOF

# 4. recovery.signal作成
touch recovery.signal

# 5. PostgreSQL開始
chown -R postgres:postgres /var/lib/postgresql/data
systemctl start postgresql

echo "リカバリ完了: ${TARGET_TIME}の状態に復旧"
```

**参考リンク：**
- [PostgreSQL Backup and Restore](https://www.postgresql.org/docs/current/backup.html)
- [PostgreSQL Point-in-Time Recovery](https://www.postgresql.org/docs/current/continuous-archiving.html)

### 9.4 バックアップ戦略の設計

**RTO（Recovery Time Objective）とRPO（Recovery Point Objective）の設定：**

```
RPO: どの程度のデータ損失を許容するか
┌─────────────────────────────────────┐
│ RPO = 1時間                         │
│ → 最大1時間分のデータ損失を許容     │
│ → バックアップ間隔: 1時間以内       │
└─────────────────────────────────────┘

RTO: どの程度の復旧時間を許容するか  
┌─────────────────────────────────────┐
│ RTO = 2時間                         │
│ → 障害発生から2時間以内に復旧完了   │
│ → 復旧手順の自動化・高速化が必要   │
└─────────────────────────────────────┘

業種別の一般的な要件:
┌────────────────┬─────────┬─────────┐
│ 業種           │ RPO     │ RTO     │
├────────────────┼─────────┼─────────┤
│ 金融（オンライン）│ 0-15分  │ 15-30分 │
│ ECサイト       │ 1-4時間 │ 1-2時間 │
│ 一般企業       │ 4-24時間│ 4-8時間 │
│ 開発環境       │ 1-7日   │ 1-2日   │
└────────────────┴─────────┴─────────┘
```

**3-2-1バックアップルールの実装：**

```bash
#!/bin/bash
# 3-2-1バックアップルール実装スクリプト

BACKUP_DIR="/backup/local"           # ローカルストレージ（1つ目のコピー）
NAS_DIR="/mnt/nas/backup"           # NAS（2つ目のコピー、異なるメディア）
CLOUD_BUCKET="s3://backup-bucket"   # クラウド（3つ目のコピー、遠隔地）

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_${DATE}.sql.gz"

echo "3-2-1バックアップルール実行開始"

# 1つ目: ローカルディスクにバックアップ
echo "1. ローカルバックアップ実行中..."
mysqldump --all-databases --single-transaction | gzip > ${BACKUP_DIR}/${BACKUP_FILE}

if [ $? -eq 0 ]; then
    echo "ローカルバックアップ成功: ${BACKUP_FILE}"
else
    echo "ローカルバックアップ失敗"
    exit 1
fi

# 2つ目: NAS（異なるメディア）にコピー
echo "2. NASにコピー中..."
cp ${BACKUP_DIR}/${BACKUP_FILE} ${NAS_DIR}/

if [ $? -eq 0 ]; then
    echo "NASコピー成功"
else
    echo "NASコピー失敗（続行）"
fi

# 3つ目: クラウド（遠隔地）にアップロード
echo "3. クラウドにアップロード中..."
aws s3 cp ${BACKUP_DIR}/${BACKUP_FILE} ${CLOUD_BUCKET}/

if [ $? -eq 0 ]; then
    echo "クラウドアップロード成功"
else
    echo "クラウドアップロード失敗（続行）"
fi

# バックアップの検証
echo "4. バックアップ検証中..."
ORIGINAL_SIZE=$(stat -c%s ${BACKUP_DIR}/${BACKUP_FILE})
NAS_SIZE=$(stat -c%s ${NAS_DIR}/${BACKUP_FILE} 2>/dev/null || echo "0")
CLOUD_SIZE=$(aws s3 ls ${CLOUD_BUCKET}/${BACKUP_FILE} --summarize | grep "Total Size" | awk '{print $3}')

echo "ファイルサイズ検証:"
echo "  ローカル: ${ORIGINAL_SIZE} bytes"
echo "  NAS: ${NAS_SIZE} bytes"  
echo "  クラウド: ${CLOUD_SIZE} bytes"

if [ "${ORIGINAL_SIZE}" = "${NAS_SIZE}" ] && [ "${ORIGINAL_SIZE}" = "${CLOUD_SIZE}" ]; then
    echo "3-2-1バックアップルール完了: 検証成功"
else
    echo "警告: ファイルサイズに差異があります"
fi
```

**自動バックアップスケジュールの設定：**

```bash
# crontab -e で設定
# 毎日深夜2時にフルバックアップ
0 2 * * * /scripts/full_backup.sh

# 6時間おきに増分バックアップ（バイナリログローテーション）
0 */6 * * * /scripts/incremental_backup.sh

# 毎週日曜日にバックアップ検証
0 4 * * 0 /scripts/backup_verification.sh

# 毎月1日に古いバックアップの削除
0 3 1 * * /scripts/cleanup_old_backups.sh
```

**バックアップ監視とアラート：**

```bash
#!/bin/bash
# バックアップ監視スクリプト

BACKUP_DIR="/backup/local"
ALERT_EMAIL="admin@company.com"
MAX_AGE_HOURS=26  # 26時間以内に作成されたバックアップが必要

# 最新バックアップファイルの確認
LATEST_BACKUP=$(ls -t ${BACKUP_DIR}/backup_*.sql.gz | head -n 1)

if [ -z "${LATEST_BACKUP}" ]; then
    echo "エラー: バックアップファイルが見つかりません" | mail -s "バックアップ異常" ${ALERT_EMAIL}
    exit 1
fi

# ファイル作成時刻の確認
FILE_AGE_HOURS=$((($(date +%s) - $(stat -c %Y ${LATEST_BACKUP})) / 3600))

if [ ${FILE_AGE_HOURS} -gt ${MAX_AGE_HOURS} ]; then
    echo "警告: 最新バックアップが${FILE_AGE_HOURS}時間前のファイルです" | mail -s "バックアップ遅延" ${ALERT_EMAIL}
    exit 1
fi

# ファイルサイズの確認（極端に小さい場合は異常）
FILE_SIZE=$(stat -c%s ${LATEST_BACKUP})
MIN_SIZE=$((100 * 1024 * 1024))  # 100MB未満は異常

if [ ${FILE_SIZE} -lt ${MIN_SIZE} ]; then
    echo "警告: バックアップファイルサイズが異常に小さいです (${FILE_SIZE} bytes)" | mail -s "バックアップサイズ異常" ${ALERT_EMAIL}
    exit 1
fi

echo "バックアップ監視OK: ${LATEST_BACKUP} (${FILE_AGE_HOURS}時間前, ${FILE_SIZE} bytes)"
```

---

## Chapter 10: ストレージとの関係

### 10.1 ストレージの種類と特性

**ストレージ階層の理解：**

データベースの性能を理解するためには、各ストレージの特性を深く理解する必要があります：

```
ストレージ階層（速い順）:
┌─────────────────────────────────────┐
│ レジスタ・キャッシュ               │ ← CPU内蔵、最高速
│ アクセス時間: < 1ns                 │
│ 容量: KB単位                        │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ メインメモリ（RAM）                 │ ← DBバッファプール
│ アクセス時間: 50-100ns              │
│ 容量: GB-TB単位                     │
│ 揮発性: 電源断で消失                │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ SSD（ソリッドステートドライブ）     │ ← 現代の主流
│ アクセス時間: 0.1-1ms               │
│ 容量: TB単位                        │
│ 耐久性: 書き込み回数に制限あり       │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ HDD（ハードディスクドライブ）       │ ← 大容量ストレージ
│ アクセス時間: 5-20ms                │
│ 容量: TB-PB単位                     │
│ 機械的可動部品あり                  │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ テープストレージ                    │ ← アーカイブ用
│ アクセス時間: 秒-分単位             │
│ 容量: PB単位                        │
│ シーケンシャルアクセスのみ          │
└─────────────────────────────────────┘
```

**なぜアクセス時間の差が重要なのか？**

具体例で理解しましょう：

```
クエリ実行時のアクセスパターン:
SELECT * FROM users WHERE age = 25;

シナリオ1: 全データがメモリ上にある場合
┌─────────────────┐
│ バッファプール  │ ← 100ns でアクセス
│ users テーブル  │
│ (全行キャッシュ) │
└─────────────────┘
実行時間: 1ms（100万行の場合）

シナリオ2: SSDからの読み取りが必要な場合  
┌─────────────────┐    ┌─────────────────┐
│ バッファプール  │    │ SSD             │
│ (空き)          │←───│ users テーブル  │ ← 0.5ms でアクセス
│                 │    │ (ディスクI/O)   │
└─────────────────┘    └─────────────────┘
実行時間: 500ms（1000回のランダムアクセス）

シナリオ3: HDDからの読み取りが必要な場合
┌─────────────────┐    ┌─────────────────┐
│ バッファプール  │    │ HDD             │
│ (空き)          │←───│ users テーブル  │ ← 10ms でアクセス
│                 │    │ (ディスクI/O)   │
└─────────────────┘    └─────────────────┘
実行時間: 10秒（1000回のランダムアクセス）

結論: ストレージの違いで 10,000倍 の性能差！
```

### 10.2 SSDの特性とデータベース最適化

**SSDの内部構造と特性：**

```
SSD内部構造:
┌─────────────────────────────────────┐
│ コントローラー                      │
│ ・FTL（Flash Translation Layer）   │
│ ・ウェアレベリング                  │
│ ・ガベージコレクション              │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ NANDフラッシュメモリ               │
│ ┌─────┬─────┬─────┬─────┬─────┐   │
│ │ブロック│ブロック│ブロック│ブロック│ブロック│   │
│ │ (512KB)│ (512KB)│ (512KB)│ (512KB)│ (512KB)│   │
│ └─────┴─────┴─────┴─────┴─────┘   │
│ 各ブロック内に複数ページ(4KB)      │
└─────────────────────────────────────┘

重要な特性:
1. ページ単位の読み書き（4KB）
2. ブロック単位の消去（512KB）  
3. 書き込み前に消去が必要
4. 書き込み回数制限（P/Eサイクル）
```

**SSDの性能特性がデータベースに与える影響：**

```
1. ランダムアクセス性能:
HDD: 200 IOPS（1秒間の入出力回数）
SSD: 100,000 IOPS
→ 500倍の性能差

2. シーケンシャルアクセス性能:  
HDD: 150 MB/s
SSD: 500 MB/s
→ 3倍程度の性能差

結論: ランダムアクセスでSSDの優位性が顕著
→ インデックススキャンで大幅な性能向上
→ OLTP（Online Transaction Processing）に最適
```

**SSD最適化のためのデータベース設定：**

```sql
-- MySQL での SSD 最適化設定
-- my.cnf での設定

[mysqld]
# I/O関連の最適化
innodb_io_capacity = 2000              # SSDの高いIOPS を活用
innodb_io_capacity_max = 4000          # 最大IOPSの設定
innodb_flush_method = O_DIRECT         # OSキャッシュをバイパス
innodb_read_io_threads = 8             # 読み取りI/Oスレッド数
innodb_write_io_threads = 8            # 書き込みI/Oスレッド数

# ページサイズの最適化
innodb_page_size = 16384               # 16KB（SSDの内部ページと整合）

# ログファイルの設定
innodb_log_file_size = 1G              # 大きなログファイル（SSDなら高速）
innodb_log_files_in_group = 2          # ログファイル数
innodb_flush_log_at_trx_commit = 1     # トランザクション毎に同期
```

**SSDの寿命を延ばす設定：**

```sql
-- 書き込み量を減らす設定
innodb_change_buffering = all          # 変更バッファリング有効
innodb_adaptive_flushing = ON          # 適応的フラッシュ
innodb_max_dirty_pages_pct = 75        # ダーティページ比率

-- WALログの設定
innodb_log_buffer_size = 64M           # ログバッファサイズ
innodb_flush_log_at_timeout = 1        # 1秒間隔での同期
```

### 10.3 ファイルシステムとの相互作用

**ファイルシステムの選択がデータベースに与える影響：**

```
主要ファイルシステムの特徴:

ext4 (Linux標準):
├─ 大容量ファイル対応（16TB）
├─ ジャーナリング機能
├─ 高い互換性
└─ 中程度の性能

XFS (高性能):
├─ 大容量対応（8EB）
├─ 並列I/O最適化
├─ 大ファイル処理高速
└─ データベース向き

ZFS (次世代):
├─ 統合的なボリューム管理
├─ データ整合性チェック
├─ スナップショット機能
├─ 圧縮・重複排除
└─ 高機能だが複雑

Btrfs (実験的):
├─ Copy-on-Write
├─ スナップショット
├─ サブボリューム
└─ まだ成熟度が低い
```

**ファイルシステムレベルでの最適化設定：**

```bash
# ext4 での最適化マウントオプション
mount -t ext4 -o noatime,data=writeback,barrier=0,commit=60 /dev/sdb1 /var/lib/mysql

# オプションの説明:
# noatime: アクセス時刻更新を無効（書き込み量削減）
# data=writeback: データ書き込みを非同期化（性能向上）
# barrier=0: 書き込みバリアを無効（UPS前提）
# commit=60: コミット間隔を60秒に延長

# XFS での最適化設定
mkfs.xfs -f -l size=256m -d agcount=32 /dev/sdb1
mount -t xfs -o noatime,logbufs=8,logbsize=256k /dev/sdb1 /var/lib/mysql

# ZFS での最適化設定  
zpool create -o ashift=12 mysql /dev/sdb1   # 4KBセクター対応
zfs create -o compression=lz4 mysql/data     # 圧縮有効
zfs create -o recordsize=16k mysql/data      # レコードサイズをInnoDBページに合わせる
```

### 10.4 ストレージ監視と性能分析

**I/O性能の監視方法：**

```bash
# iostat でのI/O監視
iostat -x 1

# 重要な指標の説明:
# %util: ディスク使用率（100%が飽和状態）
# await: 平均応答時間（ms）
# r/s, w/s: 1秒あたりの読み書き回数
# rkB/s, wkB/s: 1秒あたりの読み書きデータ量

Device    r/s   w/s    rkB/s    wkB/s  await  %util
sdb1    150.0  50.0   2400.0    800.0   5.2   45.0

# 分析:
# await > 10ms: レスポンス時間が悪化
# %util > 80%: ディスクがボトルネック
# r/s, w/s: アプリケーションの負荷パターン確認
```

```bash
# iotop でのプロセス別I/O監視
iotop -o

# MySQL プロセスのI/O状況を詳細確認
Total DISK READ:    45.67 M/s | Total DISK WRITE:   12.34 M/s
  PID  PRIO  USER     DISK READ  DISK WRITE  SWAPIN     IO>    COMMAND
 1234  be/4  mysql       25.5 M/s     8.2 M/s  0.00 % 85.2 % mysqld

# 高I/O使用プロセスの特定が可能
```

**データベースレベルでのI/O監視：**

```sql
-- MySQL での I/O 統計確認
SELECT 
    file_name,
    file_type,
    total_read,
    total_written,
    total_read / 1024 / 1024 as read_mb,
    total_written / 1024 / 1024 as written_mb
FROM performance_schema.file_summary_by_instance 
WHERE file_name LIKE '%innodb%'
ORDER BY (total_read + total_written) DESC
LIMIT 10;

-- 結果例:
-- file_name                    | read_mb | written_mb
-- /var/lib/mysql/ibdata1       | 1250.5  | 890.2
-- /var/lib/mysql/undo_001      | 450.3   | 678.9
-- /var/lib/mysql/mysql.ibd     | 234.7   | 123.4

-- テーブル別のI/O統計
SELECT 
    object_schema,
    object_name,
    count_read,
    count_write,
    sum_timer_read/1000000000 as read_seconds,
    sum_timer_write/1000000000 as write_seconds
FROM performance_schema.table_io_waits_summary_by_table 
WHERE object_schema NOT IN ('mysql', 'performance_schema', 'information_schema')
ORDER BY (sum_timer_read + sum_timer_write) DESC
LIMIT 10;
```

**ストレージボトルネック分析と対策：**

```
ボトルネック診断フローチャート:

高I/O待機時間の場合:
├─ ランダムアクセスが多い
│  ├─ インデックス不足 → インデックス追加
│  ├─ テーブルスキャン → クエリ最適化
│  └─ メモリ不足 → バッファプール拡張
│
├─ シーケンシャルアクセスが多い
│  ├─ 大量データ処理 → バッチ処理の最適化
│  ├─ フルテーブルスキャン → パーティショニング
│  └─ ログ書き込み → ログファイル分散
│
└─ ディスク飽和
   ├─ 単一ディスク → RAID構成
   ├─ HDD使用 → SSD移行  
   └─ 容量不足 → ストレージ拡張

対策の優先順位:
1. インデックス最適化（コストが低く効果大）
2. クエリチューニング（設計レベルの改善）
3. メモリ増設（ハードウェア投資）
4. ストレージ高速化（高コストだが確実）
```

**実践的なストレージ最適化戦略：**

```bash
#!/bin/bash
# ストレージ最適化スクリプト

echo "=== ストレージ性能診断 ==="

# 1. ディスク使用率確認
echo "1. ディスク使用率:"
df -h | grep -E '(Filesystem|/var/lib/mysql|/backup)'

# 2. I/O性能測定
echo "2. I/O性能（5秒間測定）:"
iostat -x 1 5 | tail -n +4

# 3. MySQL I/O統計
echo "3. MySQL I/O統計:"
mysql -e "
SELECT 
    SUBSTRING_INDEX(file_name, '/', -1) as filename,
    ROUND(total_read/1024/1024, 2) as read_mb,
    ROUND(total_written/1024/1024, 2) as written_mb,
    ROUND((total_read + total_written)/1024/1024, 2) as total_mb
FROM performance_schema.file_summary_by_instance 
WHERE file_name LIKE '%mysql%' 
ORDER BY (total_read + total_written) DESC 
LIMIT 5;
"

# 4. スロークエリ統計
echo "4. スロークエリ（I/O多消費）:"
mysql -e "
SELECT 
    digest_text,
    count_star,
    ROUND(avg_timer_wait/1000000000, 3) as avg_seconds,
    ROUND(sum_rows_examined/count_star, 0) as avg_rows_examined
FROM performance_schema.events_statements_summary_by_digest 
WHERE avg_timer_wait > 1000000000
ORDER BY sum_timer_wait DESC 
LIMIT 5;
"

# 5. 推奨事項
echo "5. 推奨事項:"
echo "   - バッファプールヒット率を99%以上に維持"
echo "   - インデックス効率を定期的に見直し"
echo "   - 大量データ処理は営業時間外に実行"
echo "   - SSD使用時は書き込み量を監視"
```

**参考リンク：**
- [MySQL Storage Engine Architecture](https://dev.mysql.com/doc/internals/en/storage-engine-architecture.html)
- [PostgreSQL Storage](https://www.postgresql.org/docs/current/storage.html)
- [Linux I/O Performance Tuning](https://www.kernel.org/doc/Documentation/block/ioprio.txt)

---

## まとめ：データベース基礎理論の完全習得

### 学習成果の確認

この拡張版基礎理論編を完了することで、以下の深い理解が身につきます：

**1. システム全体の理解：**
- ハードウェアからアプリケーションまでの階層構造
- 各層でのボトルネック要因と対策手法
- システム設計時の適切な判断基準

**2. 分散システムの理論：**
- CAP理論に基づく設計トレードオフの理解
- レプリケーション・シャーディングの適用判断
- 一貫性と可用性のバランス調整

**3. 運用レベルの実践知識：**
- バックアップ・リカバリ戦略の設計能力
- ストレージ最適化による性能向上手法
- 監視・トラブルシューティングの実践スキル

**4. 理論と実装の橋渡し：**
- 「なぜそうなるのか」の根本理解
- 新技術への応用可能な思考力
- 問題発生時の体系的なアプローチ方法

### 次のステップ：各データベース専用編へ

この基礎理論の理解を基に、以下の専用編で実践的なスキルを身につけましょう：

1. **MySQL編**: InnoDB の詳細実装とMySQL特有の最適化
2. **PostgreSQL編**: MVCC、拡張機能、JSON処理の実践
3. **Redis編**: メモリ最適化とデータ構造活用
4. **パフォーマンステスト編**: 理論を実測で検証
5. **運用実践編**: 本番環境での実践的スキル

### 継続学習のためのアドバイス

**理論の深化：**
- データベース実装の論文読解（InnoDB、PostgreSQL等）
- 分散システムの最新研究動向の追跡
- ストレージ技術の進歩に関する情報収集

**実践力の向上：**
- 本番環境でのトラブルシューティング経験
- 大規模システムの設計・運用参画
- オープンソースDBへの貢献活動

この基礎理論編で学んだ知識は、データベースエンジニアとしてのキャリア全体を通じて活用できる財産となります。表面的な操作方法ではなく、根本的な理解に基づいて判断・行動できるエンジニアを目指しましょう。