import Foundation
import SQLite3

// MARK: - 1. Data Model
struct DictItem: Identifiable, Hashable {
    var id: String { "\(entryID)|\(pronunciationOrder)|\(phonetic)|\(variantType)" }
    let word: String
    let entryID: String
    let entryAlias: String
    let wordLength: Int
    let phonetic: String
    let pinyin: String
    let pronunciationOrder: Int
    let variantType: String
    let variantPhonetic: String
    let variantPinyin: String
    let definition: String
    let radical: String
    let strokeCount: Int
    let outsideRadicalStrokes: Int
    let synonyms: String
    let antonyms: String
    let pronunciationNote: String
    let variantCharacters: String
}

// MARK: - 2. Database Manager
class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?
    
    // 設定最大收藏數量
    private let maxFavoritesCount = 30
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let dictionarySourceID = "dict_revised_2015_20260929"
    private let dictionaryColumns = "word, entry_id, entry_alias, word_length, phonetic, pinyin, pronunciation_order, variant_type, variant_phonetic, variant_pinyin, definition, radical, stroke_count, outside_radical_strokes, synonyms, antonyms, pronunciation_note, variant_characters"
    private let qualifiedDictionaryColumns = "d.word, d.entry_id, d.entry_alias, d.word_length, d.phonetic, d.pinyin, d.pronunciation_order, d.variant_type, d.variant_phonetic, d.variant_pinyin, d.definition, d.radical, d.stroke_count, d.outside_radical_strokes, d.synonyms, d.antonyms, d.pronunciation_note, d.variant_characters"
    
    private init() {
        openDatabase()
        createTables()
        migrateDictionaryIfNeeded()
    }
    
    // MARK: - Database Setup (關鍵修正：複製到可寫入目錄)
    
    /// 取得沙盒中 Documents 目錄下的資料庫路徑 (可讀寫)
    private func getWritableDBPath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let documentsDirectory = paths[0]
        return (documentsDirectory as NSString).appendingPathComponent("dictionary.sqlite")
    }
    
    private func openDatabase() {
        let writablePath = getWritableDBPath()
        let fileManager = FileManager.default
        
        // 1. 檢查可寫入目錄是否存在資料庫
        if !fileManager.fileExists(atPath: writablePath) {
            print("📂 初次執行，準備將資料庫從 Bundle 複製到 Documents...")
            // 如果不存在，從 App Bundle 中尋找原始檔案
            guard let bundlePath = Bundle.main.path(forResource: "dictionary", ofType: "sqlite") else {
                print("❌ Fatal Error: 在 Bundle 中找不到 dictionary.sqlite 原始檔！請確認檔案有加入專案。")
                return
            }
            
            // 嘗試複製
            do {
                try fileManager.copyItem(atPath: bundlePath, toPath: writablePath)
                print("✅ 資料庫複製成功！路徑: \(writablePath)")
            } catch {
                print("❌ 資料庫複製失敗: \(error)")
                return
            }
        } else {
            print("📂 資料庫已存在於可寫入目錄，直接使用。")
        }
        
        // 2. 開啟位於可寫入目錄的資料庫
        if sqlite3_open(writablePath, &db) != SQLITE_OK {
            print("❌ Error: 無法開啟資料庫。")
            if let errorPointer = sqlite3_errmsg(db) {
                let errorMessage = String(cString: errorPointer)
                print("   SQLite Error: \(errorMessage)")
            }
        } else {
            print("✅ 資料庫連線成功。")
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        // favorites 表格：使用 word 當主鍵。
        // 注意：SQLite 預設有隱藏的 rowid 欄位，可用來判斷加入順序 (越小越早加入)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS favorites (word TEXT PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS history (word TEXT PRIMARY KEY, timestamp REAL);", nil, nil, nil)
    }

    /// 更新既有使用者沙盒中的舊版資料庫，但保留收藏與查詢紀錄。
    private func migrateDictionaryIfNeeded() {
        guard let db = db,
              let bundlePath = Bundle.main.path(forResource: "dictionary", ofType: "sqlite") else { return }

        sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS dictionary_metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);", nil, nil, nil)
        var stmt: OpaquePointer?
        var sourceID = ""
        if sqlite3_prepare_v2(db, "SELECT value FROM dictionary_metadata WHERE key = 'source_id' LIMIT 1;", -1, &stmt, nil) == SQLITE_OK,
           sqlite3_step(stmt) == SQLITE_ROW,
           let pointer = sqlite3_column_text(stmt, 0) {
            sourceID = String(cString: pointer)
        }
        sqlite3_finalize(stmt)
        guard sourceID != dictionarySourceID else { return }

        // 以 ATTACH 方式載入新詞庫，避免清掉使用者的 favorites/history。
        // 不使用 CREATE TABLE ... AS SELECT，因為那會遺失欄位型別、NOT NULL、
        // DEFAULT 與 AUTOINCREMENT 等 schema 資訊。
        let escapedPath = bundlePath.replacingOccurrences(of: "'", with: "''")
        let migrationSQL = """
            ATTACH DATABASE '\(escapedPath)' AS bundled_dictionary;
            BEGIN IMMEDIATE TRANSACTION;
            DROP TABLE IF EXISTS dict_mini;
            CREATE TABLE dict_mini (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word TEXT NOT NULL,
                entry_alias TEXT NOT NULL DEFAULT '',
                word_length INTEGER NOT NULL DEFAULT 0,
                entry_id TEXT NOT NULL DEFAULT '',
                radical TEXT NOT NULL DEFAULT '',
                stroke_count INTEGER NOT NULL DEFAULT 0,
                outside_radical_strokes INTEGER NOT NULL DEFAULT 0,
                pronunciation_order INTEGER NOT NULL DEFAULT 0,
                phonetic TEXT NOT NULL DEFAULT '',
                variant_type TEXT NOT NULL DEFAULT '',
                variant_phonetic TEXT NOT NULL DEFAULT '',
                pinyin TEXT NOT NULL DEFAULT '',
                variant_pinyin TEXT NOT NULL DEFAULT '',
                synonyms TEXT NOT NULL DEFAULT '',
                antonyms TEXT NOT NULL DEFAULT '',
                definition TEXT NOT NULL DEFAULT '',
                pronunciation_note TEXT NOT NULL DEFAULT '',
                variant_characters TEXT NOT NULL DEFAULT ''
            );
            INSERT INTO dict_mini (
                word, entry_alias, word_length, entry_id, radical, stroke_count,
                outside_radical_strokes, pronunciation_order, phonetic, variant_type,
                variant_phonetic, pinyin, variant_pinyin, synonyms, antonyms,
                definition, pronunciation_note, variant_characters
            )
            SELECT
                word, entry_alias, word_length, entry_id, radical, stroke_count,
                outside_radical_strokes, pronunciation_order, phonetic, variant_type,
                variant_phonetic, pinyin, variant_pinyin, synonyms, antonyms,
                definition, pronunciation_note, variant_characters
            FROM bundled_dictionary.dict_mini;
            CREATE INDEX IF NOT EXISTS idx_dict_word ON dict_mini(word);
            CREATE INDEX IF NOT EXISTS idx_dict_phonetic ON dict_mini(phonetic);
            CREATE INDEX IF NOT EXISTS idx_dict_pinyin ON dict_mini(pinyin);
            CREATE INDEX IF NOT EXISTS idx_dict_word_length ON dict_mini(word, word_length);
            DELETE FROM dictionary_metadata;
            INSERT INTO dictionary_metadata(key, value)
                SELECT key, value FROM bundled_dictionary.dictionary_metadata;
            INSERT OR REPLACE INTO dictionary_metadata(key, value)
                VALUES ('source_id', '\(dictionarySourceID)');
            PRAGMA user_version = 2;
            COMMIT;
            DETACH DATABASE bundled_dictionary;
        """
        if sqlite3_exec(db, migrationSQL, nil, nil, nil) != SQLITE_OK {
            if let errorPointer = sqlite3_errmsg(db) {
                print("❌ 字典資料更新失敗: \(String(cString: errorPointer))")
            }
            // sqlite3_exec 失敗時，交易與 ATTACH 可能仍然存在；清理狀態後才能
            // 讓下一次啟動重新嘗試，而不會留下半套字典或鎖定資料庫。
            sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
            sqlite3_exec(db, "DETACH DATABASE bundled_dictionary;", nil, nil, nil)
        } else {
            print("✅ 已切換至教育部《重編國語辭典修訂本》資料")
        }
    }
    
    // MARK: - 🔍 主搜尋 (字典邏輯：僅限字首匹配 + 權重排序)
    func search(keyword: String) -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        
        // LIKE 前綴比對不會用到索引，會把 16 萬筆整表掃描。改成索引範圍查詢。
        let querySQL = """
            SELECT \(dictionaryColumns)
            FROM dict_mini
            WHERE rowid IN (
                SELECT rowid FROM dict_mini WHERE word >= ?1 AND word < ?2
                UNION
                SELECT rowid FROM dict_mini WHERE phonetic >= ?1 AND phonetic < ?2
                UNION
                SELECT rowid FROM dict_mini WHERE pinyin >= ?3 AND pinyin < ?4
            )
            ORDER BY
              CASE WHEN word = ?5 THEN 0 ELSE 1 END ASC,
              word_length ASC,
              stroke_count ASC,
              pronunciation_order ASC
            LIMIT 50;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let (lower, upper) = prefixBounds(keyword)
            let (pinyinLower, pinyinUpper) = prefixBounds(keyword.lowercased())
            bindText(stmt, index: 1, value: lower)
            bindText(stmt, index: 2, value: upper)
            bindText(stmt, index: 3, value: pinyinLower)
            bindText(stmt, index: 4, value: pinyinUpper)
            bindText(stmt, index: 5, value: keyword)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    // MARK: - ⌨️ 鍵盤候選字搜尋
    func searchByPhonetic(_ bopomofo: String) -> [String] {
        var rawResults: [String] = []
        guard let db = db else { return [] }
        
        let querySQL = """
            SELECT word
            FROM dict_mini
            WHERE phonetic >= ?1 AND phonetic < ?2 AND word_length = 1
            GROUP BY word
            ORDER BY MIN(length(phonetic)) ASC, MIN(stroke_count) ASC
            LIMIT 60;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, querySQL, -1, &stmt, nil) == SQLITE_OK {
            let (lower, upper) = prefixBounds(bopomofo)
            bindText(stmt, index: 1, value: lower)
            bindText(stmt, index: 2, value: upper)
            
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let wordPtr = sqlite3_column_text(stmt, 0) {
                    rawResults.append(String(cString: wordPtr))
                }
            }
        }
        sqlite3_finalize(stmt)
        return rawResults
    }

    /// 相似詞、相反詞點進去時，取這個字詞的第一筆讀音。
    func lookupExact(word: String) -> DictItem? {
        guard let db = db else { return nil }
        let sql = """
            SELECT \(dictionaryColumns)
            FROM dict_mini
            WHERE word = ?
            ORDER BY pronunciation_order ASC, stroke_count ASC
            LIMIT 1;
        """
        var stmt: OpaquePointer?
        var item: DictItem?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: word)
            if sqlite3_step(stmt) == SQLITE_ROW {
                item = parseRow(stmt: stmt)
            }
        }
        sqlite3_finalize(stmt)
        return item
    }

    /// 前綴的不含上界。U+10FFFF 是最大字元，接在前綴後面可涵蓋所有更長的字。
    private func prefixBounds(_ keyword: String) -> (String, String) {
        (keyword, keyword + "\u{10FFFF}")
    }
    
    // MARK: - History (歷史紀錄)
    func addToHistory(word: String) {
        guard let db = db else { return }
        let timestamp = Date().timeIntervalSince1970
        let insertSQL = "INSERT OR REPLACE INTO history (word, timestamp) VALUES (?, ?);"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: word)
            sqlite3_bind_double(stmt, 2, timestamp)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        // 保持歷史紀錄最新的 50 筆
        sqlite3_exec(db, "DELETE FROM history WHERE word NOT IN (SELECT word FROM history ORDER BY timestamp DESC LIMIT 50);", nil, nil, nil)
    }
    
    func getHistory() -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        let sql = "SELECT \(qualifiedDictionaryColumns) FROM history h INNER JOIN dict_mini d ON h.word = d.word ORDER BY h.timestamp DESC"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    func clearHistory() {
        guard let db = db else { return }
        sqlite3_exec(db, "DELETE FROM history;", nil, nil, nil)
    }
    
    // MARK: - Favorites (收藏 - 限制 30 筆)
    
    /// 切換收藏狀態：若已收藏則刪除，若未收藏則加入 (若滿 30 筆則刪除最舊的)
    func toggleFavorite(word: String) -> Bool {
        guard let db = db else {
            print("❌ DB Error: 資料庫未連接")
            return false
        }
        
        if isFavorite(word: word) {
            // --- 情況 A：已收藏，執行刪除 ---
            print("🗑️ 正在從收藏移除: \(word)")
            let deleteSQL = "DELETE FROM favorites WHERE word = ?;"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, index: 1, value: word)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ 移除成功")
                } else {
                    print("❌ 移除失敗 SQL Error")
                }
            }
            sqlite3_finalize(stmt)
            return false // 回傳 false 代表現在「未收藏」
            
        } else {
            // --- 情況 B：未收藏，準備加入 ---
            print("❤️ 準備加入收藏: \(word)")
            
            // 1. 檢查目前數量
            var currentCount = 0
            let countSQL = "SELECT count(*) FROM favorites;"
            var countStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, countSQL, -1, &countStmt, nil) == SQLITE_OK {
                if sqlite3_step(countStmt) == SQLITE_ROW {
                    currentCount = Int(sqlite3_column_int(countStmt, 0))
                }
            }
            sqlite3_finalize(countStmt)
            print("📊 目前收藏數量: \(currentCount)")
            
            // 2. 如果達到上限，刪除「最舊」的一筆
            // 這裡使用 SQLite 的 rowid 來判斷，rowid 最小的代表最早插入
            if currentCount >= maxFavoritesCount {
                print("⚠️ 達到收藏上限 (\(maxFavoritesCount))，正在刪除最舊的一筆...")
                let deleteOldestSQL = "DELETE FROM favorites WHERE rowid = (SELECT min(rowid) FROM favorites);"
                if sqlite3_exec(db, deleteOldestSQL, nil, nil, nil) == SQLITE_OK {
                     print("✅ 舊資料刪除成功")
                } else {
                     print("❌ 舊資料刪除失敗")
                }
            }
            
            // 3. 插入新收藏
            let insertSQL = "INSERT INTO favorites (word) VALUES (?);"
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, insertSQL, -1, &stmt, nil) == SQLITE_OK {
                bindText(stmt, index: 1, value: word)
                if sqlite3_step(stmt) == SQLITE_DONE {
                    print("✅ 加入收藏成功: \(word)")
                } else {
                    print("❌ 加入失敗 (可能是 SQL 錯誤或約束衝突): \(word)")
                    if let errorPointer = sqlite3_errmsg(db) {
                        print("   SQLite Error: \(String(cString: errorPointer))")
                    }
                }
            }
            sqlite3_finalize(stmt)
            
            return true // 回傳 true 代表現在「已收藏」
        }
    }
    
    func isFavorite(word: String) -> Bool {
        guard let db = db else { return false }
        let sql = "SELECT count(*) FROM favorites WHERE word = ?;"
        var stmt: OpaquePointer?
        var count = 0
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            bindText(stmt, index: 1, value: word)
            if sqlite3_step(stmt) == SQLITE_ROW {
                count = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        return count > 0
    }
    
    // 取得所有收藏列表 (UI 需要此函式)
    func getFavorites() -> [DictItem] {
        var result: [DictItem] = []
        guard let db = db else { return [] }
        
        // 聯表查詢：從 favorites 取得單字，再從 dict_mini 取得詳細解釋
        // ORDER BY f.rowid DESC 確保最新加入的顯示在最上面
        let sql = """
            SELECT \(qualifiedDictionaryColumns)
            FROM favorites f 
            INNER JOIN dict_mini d ON f.word = d.word 
            ORDER BY f.rowid DESC;
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(parseRow(stmt: stmt))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
    
    // MARK: - Helper
    /// SQLITE_TRANSIENT 會自行複製字串。傳 nil 等於 SQLITE_STATIC，暫時的 UTF-8 指標可能在查詢前就被釋放。
    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(stmt, index, (value as NSString).utf8String, -1, sqliteTransient)
    }

    private func parseRow(stmt: OpaquePointer?) -> DictItem {
        func text(_ index: Int32) -> String {
            guard let pointer = sqlite3_column_text(stmt, index) else { return "" }
            return String(cString: pointer)
        }
        let word = text(0)
        let entryID = text(1)
        let entryAlias = text(2)
        let wordLength = Int(sqlite3_column_int(stmt, 3))
        let phonetic = text(4)
        let pinyin = text(5)
        let pronunciationOrder = Int(sqlite3_column_int(stmt, 6))
        let variantType = text(7)
        let variantPhonetic = text(8)
        let variantPinyin = text(9)
        let definition = text(10)
        let radical = text(11)
        let strokeCount = Int(sqlite3_column_int(stmt, 12))
        let outsideRadicalStrokes = Int(sqlite3_column_int(stmt, 13))
        let synonyms = text(14)
        let antonyms = text(15)
        let pronunciationNote = text(16)
        let variantCharacters = text(17)
        return DictItem(word: word, entryID: entryID, entryAlias: entryAlias, wordLength: wordLength, phonetic: phonetic, pinyin: pinyin, pronunciationOrder: pronunciationOrder, variantType: variantType, variantPhonetic: variantPhonetic, variantPinyin: variantPinyin, definition: definition, radical: radical, strokeCount: strokeCount, outsideRadicalStrokes: outsideRadicalStrokes, synonyms: synonyms, antonyms: antonyms, pronunciationNote: pronunciationNote, variantCharacters: variantCharacters)
    }
}
