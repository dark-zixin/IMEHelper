import Foundation

private struct TestFailure: Error {
    let name: String
}

private func expect(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
    guard try condition() else { throw TestFailure(name: name) }
}

private func expectFailure<T>(_ name: String, _ action: () throws -> T) throws {
    do {
        _ = try action()
        throw TestFailure(name: name)
    } catch is TestFailure {
        throw TestFailure(name: name)
    } catch {
        return
    }
}

@main
struct CangjieModelsTestRunner {
    static func main() {
        do {
            try run()
            print("PASS：倉頡模型測試全部通過")
        } catch let error as TestFailure {
            fputs("FAIL：\(error.name)\n", stderr)
            exit(1)
        } catch {
            fputs("FAIL：未預期測試錯誤\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        let args = CommandLine.arguments
        guard args.count == 2 || args.count == 3 else {
            throw TestFailure(name: "參數需為真碼表路徑及可選的 app bundle 路徑")
        }
        try dictionaryTests(resourceURL: URL(fileURLWithPath: args[1]), bundlePath: args.count == 3 ? args[2] : nil)
        try savedListTests()
    }

    private static func dictionaryTests(resourceURL: URL, bundlePath: String?) throws {
        let dictionary = try CangjieDictionary(resourceURL: resourceURL)
        let expected = [
            CangjieCharacterResult(character: "具", codes: ["bmmc"]),
            CangjieCharacterResult(character: "曰", codes: ["a", "xa"]),
            CangjieCharacterResult(character: "晷", codes: ["ahor", "ahyr"]),
            CangjieCharacterResult(character: "𠀀", codes: ["mls"]),
            CangjieCharacterResult(character: "在", codes: ["klg"])
        ]
        try expect(dictionary.lookup("具曰晷𠀀在") == expected, "真碼表固定字碼與排序")
        try expect(CangjieDictionary.radicals(for: "abcdefghijklmnopqrstuvwxyz") == "日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重", "完整字根對應")

        if let bundlePath {
            guard let bundle = Bundle(url: URL(fileURLWithPath: bundlePath)) else {
                throw TestFailure(name: "無法開啟 app bundle")
            }
            let bundled = try CangjieDictionary.load(bundle: bundle)
            try expect(bundled.lookup("具曰晷𠀀在") == expected, "真 app bundle 資源接線")
        }
        try expectFailure("缺少 bundle 資源必須失敗") {
            try CangjieDictionary.load()
        }

        let fixture = try makeDirectory().appendingPathComponent("fixture.tsv")
        try "甲\txa\n甲\tb\n甲\ta\n甲\tb\n甲\txb\n乙\tzz\n".write(to: fixture, atomically: true, encoding: .utf8)
        let sample = try CangjieDictionary(resourceURL: fixture)
        try expect(sample.lookup("甲乙甲 ?🙂") == [
            CangjieCharacterResult(character: "甲", codes: ["b", "a", "xa", "xb"]),
            CangjieCharacterResult(character: "乙", codes: ["zz"]),
            CangjieCharacterResult(character: "甲", codes: ["b", "a", "xa", "xb"]),
            CangjieCharacterResult(character: " ", codes: []),
            CangjieCharacterResult(character: "?", codes: []),
            CangjieCharacterResult(character: "🙂", codes: [])
        ], "人工樣本一般碼優先、組內原序、去重與原字保留")

        let malformed = try makeDirectory().appendingPathComponent("malformed.tsv")
        try "甲\ta\n錯誤資料\n".write(to: malformed, atomically: true, encoding: .utf8)
        try expectFailure("壞碼表必須失敗") {
            try CangjieDictionary(resourceURL: malformed)
        }
        try expectFailure("碼表讀取失敗必須回傳錯誤") {
            try CangjieDictionary(resourceURL: try makeDirectory())
        }
    }

    private static func savedListTests() throws {
        try saveAndResave()
        try legacyConversion()
        try failureCases()
        try diagnosticReasonCases()
    }

    private static func saveAndResave() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("saved.json")
        let store = try CangjieSavedListStore(fileURL: file)
        try expect(store.entries.isEmpty && !FileManager.default.fileExists(atPath: file.path), "首次空檔不得假裝寫過")

        let first = try store.save(CangjieCharacterResult(character: "具", codes: ["bmmc"]))
        let second = try store.save(CangjieCharacterResult(character: "曰", codes: ["a", "xa"]))
        _ = try store.save(CangjieCharacterResult(character: "晷", codes: ["ahor", "ahyr"]))
        _ = try store.save(CangjieCharacterResult(character: "𠀀", codes: ["mls"]))
        try expect(store.entries.prefix(3).map(\.character) == ["𠀀", "晷", "曰"], "近期三字按保存順序")
        Thread.sleep(forTimeInterval: 0.02)
        let resaved: CangjieSavedEntry
        do {
            resaved = try store.save(CangjieCharacterResult(character: "曰", codes: ["xq", "a", "b"]))
        } catch {
            throw TestFailure(name: "重存同字排前且不重複")
        }
        try expect(resaved.id == second.id && resaved.savedAt > second.savedAt, "重存沿用 UUID 並更新時間")
        try expect(store.entries.map(\.character) == ["曰", "𠀀", "晷", "具"], "重存同字排前且不重複")
        try expect(store.entries[0].codes == ["xq", "a", "b"], "重存覆蓋本次完整字碼")
        try expect(store.entries.prefix(3).map(\.character) == ["曰", "𠀀", "晷"], "重存後近期三字")

        let persisted = try CangjieSavedListStore(fileURL: file)
        try expect(persisted.entries == store.entries, "存後全新實例重讀順序")
        let savedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        try expect(savedJSON?["schemaVersion"] as? Int == 2, "儲存檔版本欄")
        try expect(persisted.entries.last?.id == first.id, "新增項 UUID 往返")

        let decomposed = "e\u{0301}"
        let composed = "\u{00E9}"
        let firstVariant = try persisted.save(CangjieCharacterResult(character: decomposed, codes: ["a"]))
        let secondVariant = try persisted.save(CangjieCharacterResult(character: composed, codes: ["b"]))
        try expect(firstVariant.id != secondVariant.id, "正規等價但 scalar 不同的字保留兩項")
        try expect(persisted.entries.prefix(2).map { $0.character.unicodeScalars.map(\.value) } == [[233], [101, 769]], "原始 scalar 字鍵不合併")
        let refreshedVariant = try persisted.save(CangjieCharacterResult(character: decomposed, codes: ["c"]))
        try expect(refreshedVariant.id == firstVariant.id && persisted.entries.prefix(2).map(\.id) == [firstVariant.id, secondVariant.id], "原始 scalar 字鍵重存只動同字")
        try expect(persisted.entries[0].codes == ["c"], "原始 scalar 字鍵重存換碼")

        let beforeInvalidSave = try Data(contentsOf: file)
        let beforeInvalidEntries = persisted.entries
        for result in [
            CangjieCharacterResult(character: "具曰", codes: ["a"]),
            CangjieCharacterResult(character: " ", codes: []),
            CangjieCharacterResult(character: "", codes: []),
            CangjieCharacterResult(character: "具", codes: [""]),
            CangjieCharacterResult(character: "具", codes: ["A"]),
            CangjieCharacterResult(character: "具", codes: ["a1"])
        ] {
            try expectFailure("無效單字或字碼必須拒絕") { try persisted.save(result) }
            try expect(persisted.entries == beforeInvalidEntries, "無效保存不得改記憶體")
            try expect((try Data(contentsOf: file)) == beforeInvalidSave, "無效保存不得覆蓋舊檔")
        }

        guard var duplicateJSON = savedJSON,
              let savedEntries = duplicateJSON["entries"] as? [[String: Any]],
              let firstSavedEntry = savedEntries.first else {
            throw TestFailure(name: "測試檔 JSON 結構")
        }
        duplicateJSON["entries"] = [firstSavedEntry, firstSavedEntry]
        let duplicateFile = try makeDirectory().appendingPathComponent("duplicate.json")
        try JSONSerialization.data(withJSONObject: duplicateJSON).write(to: duplicateFile)
        try expectFailure("重複 UUID 的清單必須拒絕") {
            try CangjieSavedListStore(fileURL: duplicateFile)
        }

        var duplicateCharacterJSON = savedJSON!
        var distinctIDEntries = savedEntries
        distinctIDEntries[1]["character"] = firstSavedEntry["character"]
        duplicateCharacterJSON["entries"] = distinctIDEntries
        let duplicateCharacterFile = try makeDirectory().appendingPathComponent("duplicate-character.json")
        try JSONSerialization.data(withJSONObject: duplicateCharacterJSON).write(to: duplicateCharacterFile)
        try expectFailure("重複原始字鍵的清單必須拒絕") {
            try CangjieSavedListStore(fileURL: duplicateCharacterFile)
        }

        var invalidCodeJSON = savedJSON!
        var invalidCodeEntries = savedEntries
        invalidCodeEntries[0]["codes"] = ["A"]
        invalidCodeJSON["entries"] = invalidCodeEntries
        let invalidCodeFile = try makeDirectory().appendingPathComponent("invalid-code.json")
        try JSONSerialization.data(withJSONObject: invalidCodeJSON).write(to: invalidCodeFile)
        try expectFailure("v2 讀取無效字碼必須拒絕") {
            try CangjieSavedListStore(fileURL: invalidCodeFile)
        }

        try persisted.remove(id: first.id)
        let afterRemove = try CangjieSavedListStore(fileURL: file)
        try expect(!afterRemove.entries.contains(where: { $0.id == first.id }) && afterRemove.entries.count == beforeInvalidEntries.count - 1, "刪後全新實例重讀")

        let unknownFile = try makeDirectory().appendingPathComponent("unknown.json")
        let unknownStore = try CangjieSavedListStore(fileURL: unknownFile)
        let unknown = try unknownStore.save(CangjieCharacterResult(character: "🙂", codes: []))
        try expect((try CangjieSavedListStore(fileURL: unknownFile)).entries == [unknown], "未知字空碼陣列可保存與重讀")

        let oldBytes = try Data(contentsOf: file)
        let oldEntries = afterRemove.entries
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        try expectFailure("寫入失敗應回傳錯誤") {
            try afterRemove.save(CangjieCharacterResult(character: "具", codes: ["bmmc"]))
        }
        try expect(afterRemove.entries == oldEntries, "寫入失敗不得先改記憶體")
        try expect((try Data(contentsOf: file)) == oldBytes, "寫入失敗須保留舊檔 bytes")
        try expectFailure("刪除寫入失敗應回傳錯誤") {
            try afterRemove.remove(id: second.id)
        }
        try expect(afterRemove.entries == oldEntries, "刪除寫入失敗不得先改記憶體")
        try expect((try Data(contentsOf: file)) == oldBytes, "刪除寫入失敗須保留舊檔 bytes")
    }

    private static func legacyConversion() throws {
        let fixture = #"""
        {"schemaVersion":1,"entries":[
          {"id":"11111111-1111-1111-1111-111111111111","text":"\u0065\u0301\u66f0 \u0065\u0301","characters":[
            {"character":"\u0065\u0301","codes":["a"]},
            {"character":"\u66f0","codes":["xa","a"]},
            {"character":" ","codes":[]},
            {"character":"\u0065\u0301","codes":["a"]}
          ],"createdAt":100},
          {"id":"22222222-2222-2222-2222-222222222222","text":"\u00e9\u66f0","characters":[
            {"character":"\u00e9","codes":["b"]},
            {"character":"\u66f0","codes":["a","b","xa"]}
          ],"createdAt":50}
        ]}
        """#
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("legacy.json")
        let originalBytes = Data(fixture.utf8)
        try originalBytes.write(to: file)
        let store: CangjieSavedListStore
        do {
            store = try CangjieSavedListStore(fileURL: file)
        } catch {
            throw TestFailure(name: "v1 字面 JSON 轉換載入")
        }
        try expect(store.entries.map { $0.character.unicodeScalars.map(\.value) } == [[101, 769], [26352], [233]], "v1 轉換保留字序與原始 scalar")
        try expect(store.entries.map(\.codes) == [["a"], ["a", "b", "xa"], ["b"]], "v1 轉換合併碼並穩定排序")
        try expect(store.entries.map(\.savedAt) == [Date(timeIntervalSinceReferenceDate: 100), Date(timeIntervalSinceReferenceDate: 100), Date(timeIntervalSinceReferenceDate: 50)], "v1 轉換保留首見時間")
        try expect((try Data(contentsOf: file)) == originalBytes, "v1 載入不得改檔")

        let beforeFailure = store.entries
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
            try expectFailure("v1 首次寫入失敗應回傳錯誤") {
                try store.save(CangjieCharacterResult(character: "曰", codes: ["a", "xa"]))
            }
            try expect(store.entries == beforeFailure, "v1 首次寫入失敗保留記憶體")
            try expect((try Data(contentsOf: file)) == originalBytes, "v1 首次寫入失敗保留原檔 bytes")
        }

        let saved = try store.save(CangjieCharacterResult(character: "曰", codes: ["a", "xa"]))
        try expect(saved.id == beforeFailure[1].id && store.entries[0].character == "曰", "v1 首次成功保存沿用轉換項 UUID")
        let migratedData = try Data(contentsOf: file)
        let migratedJSON = try JSONSerialization.jsonObject(with: migratedData) as? [String: Any]
        try expect(migratedJSON?["schemaVersion"] as? Int == 2, "v1 首次成功保存寫 v2")
        try expect((try CangjieSavedListStore(fileURL: file)).entries == store.entries, "v1 首寫後全新實例讀 v2")

        let deleteFile = directory.appendingPathComponent("legacy-delete.json")
        try originalBytes.write(to: deleteFile)
        let deleting = try CangjieSavedListStore(fileURL: deleteFile)
        try deleting.remove(id: deleting.entries[0].id)
        let deletedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: deleteFile)) as? [String: Any]
        try expect(deletedJSON?["schemaVersion"] as? Int == 2, "v1 首次刪除寫 v2")
        try expect((try CangjieSavedListStore(fileURL: deleteFile)).entries.count == 2, "v1 首刪後全新實例重讀")

        let invalidFile = directory.appendingPathComponent("legacy-invalid.json")
        try #"{"schemaVersion":1,"entries":[{"id":"11111111-1111-1111-1111-111111111111","text":"甲","characters":[{"character":"乙","codes":["a"]}],"createdAt":100}]}"#.write(to: invalidFile, atomically: true, encoding: .utf8)
        let invalidBytes = try Data(contentsOf: invalidFile)
        try expectFailure("v1 原文 scalar 與字列不符必須拒絕") { try CangjieSavedListStore(fileURL: invalidFile) }
        try expect((try Data(contentsOf: invalidFile)) == invalidBytes, "v1 轉換失敗保留原檔 bytes")

        let duplicateIDFile = directory.appendingPathComponent("legacy-duplicate-id.json")
        let duplicateID = fixture.replacingOccurrences(of: "22222222-2222-2222-2222-222222222222", with: "11111111-1111-1111-1111-111111111111")
        try duplicateID.write(to: duplicateIDFile, atomically: true, encoding: .utf8)
        try expectFailure("v1 重複 UUID 必須拒絕") { try CangjieSavedListStore(fileURL: duplicateIDFile) }

        let invalidCodeFile = directory.appendingPathComponent("legacy-invalid-code.json")
        let invalidCode = fixture.replacingOccurrences(of: #""codes":["b"]"#, with: #""codes":["B"]"#)
        try invalidCode.write(to: invalidCodeFile, atomically: true, encoding: .utf8)
        try expectFailure("v1 無效字碼必須拒絕") { try CangjieSavedListStore(fileURL: invalidCodeFile) }
    }

    private static func failureCases() throws {

        let corrupt = try makeDirectory().appendingPathComponent("corrupt.json")
        let secret = "敏感原文換行\n偽造欄位=危險"
        try "{\"schemaVersion\":2,\"entries\":\"\(secret)\"}".write(to: corrupt, atomically: true, encoding: .utf8)
        let corruptBytes = try Data(contentsOf: corrupt)
        try expectFailure("壞 JSON 不可建立可寫清單") {
            try CangjieSavedListStore(fileURL: corrupt)
        }
        try expect((try Data(contentsOf: corrupt)) == corruptBytes, "壞 JSON 不得覆蓋")

        let future = try makeDirectory().appendingPathComponent("future.json")
        try "{\"schemaVersion\":3,\"entries\":[]}".write(to: future, atomically: true, encoding: .utf8)
        let futureBytes = try Data(contentsOf: future)
        try expectFailure("不支援版本不可建立可寫清單") {
            try CangjieSavedListStore(fileURL: future)
        }
        try expect((try Data(contentsOf: future)) == futureBytes, "不支援版本不得覆蓋")

        let unreadable = try makeDirectory()
        try expectFailure("讀取目錄當 JSON 必須失敗") {
            try CangjieSavedListStore(fileURL: unreadable)
        }

        let parentFile = try makeDirectory().appendingPathComponent("普通檔")
        try FileManager.default.createDirectory(at: parentFile, withIntermediateDirectories: true)
        let blocked = try CangjieSavedListStore(fileURL: parentFile.appendingPathComponent("saved.json"))
        try FileManager.default.removeItem(at: parentFile)
        try "原檔內容".write(to: parentFile, atomically: true, encoding: .utf8)
        try expectFailure("父路徑為普通檔時寫入必須失敗") {
            try blocked.save(CangjieCharacterResult(character: "具", codes: ["bmmc"]))
        }
        try expect(blocked.entries.isEmpty, "父路徑失敗不得改記憶體")
        try expect((try String(contentsOf: parentFile, encoding: .utf8)) == "原檔內容", "父路徑失敗不得改原檔")
    }

    private static func diagnosticReasonCases() throws {
        let idA = "11111111-1111-1111-1111-111111111111"
        let idB = "22222222-2222-2222-2222-222222222222"
        let first = #"{"id":"\#(idA)","character":"甲","codes":["a"],"savedAt":100}"#
        let second = #"{"id":"\#(idB)","character":"乙","codes":["b"],"savedAt":200}"#

        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[\#(first),\#(first)]}"#, "診斷 v2 重複 UUID")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[\#(first),{"id":"\#(idA)","character":"甲乙","codes":["a"],"savedAt":100}]}"#, "診斷 v2 UUID 優先於字元")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[\#(first),{"id":"\#(idB)","character":"甲","codes":["b"],"savedAt":200}]}"#, "診斷 v2 重複原始字鍵")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[\#(first),{"id":"\#(idB)","character":"甲","codes":["A"],"savedAt":200}]}"#, "診斷 v2 字鍵優先於碼")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[{"id":"\#(idA)","character":"甲乙","codes":["a"],"savedAt":100}]}"#, "診斷 v2 非單字")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[{"id":"\#(idA)","character":" ","codes":[],"savedAt":100}]}"#, "診斷 v2 空白字")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[{"id":"\#(idA)","character":"甲","codes":["A"],"savedAt":100}]}"#, "診斷 v2 無效碼")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[{"id":"\#(idA)","character":"甲","codes":["a"],"savedAt":"壞日期"}]}"#, "診斷 v2 日期型別錯誤")
        try expectMalformedFixture(#"{"schemaVersion":2,"entries":[\#(first),\#(second)],"other":"敏感原文換行"}"#, "診斷 v2 合法欄位", expectedCount: 2)

        let legacyA = #"{"id":"\#(idA)","text":"甲","characters":[{"character":"甲","codes":["a"]}],"createdAt":100}"#
        try expectMalformedFixture(#"{"schemaVersion":1,"entries":[\#(legacyA),\#(legacyA)]}"#, "診斷 v1 重複 UUID")
        try expectMalformedFixture(#"{"schemaVersion":1,"entries":[\#(legacyA),{"id":"\#(idA)","text":"乙","characters":[{"character":"甲","codes":["a"]}],"createdAt":100}]}"#, "診斷 v1 UUID 優先於原文")
        try expectMalformedFixture(#"{"schemaVersion":1,"entries":[{"id":"\#(idA)","text":"甲乙","characters":[{"character":"甲乙","codes":["a"]}],"createdAt":100}]}"#, "診斷 v1 非單字")
        try expectMalformedFixture(#"{"schemaVersion":1,"entries":[{"id":"\#(idA)","text":"甲","characters":[{"character":"甲","codes":[""]}],"createdAt":100}]}"#, "診斷 v1 空碼字串")
        try expectMalformedFixture(#"{"schemaVersion":1,"entries":[{"id":"\#(idA)","text":"乙","characters":[{"character":"甲","codes":["a"]}],"createdAt":100}]}"#, "診斷 v1 原文不符")
        try expectMalformedFixture(#"{"schemaVersion":1,"entries":[{"id":"\#(idA)","text":" ","characters":[{"character":" ","codes":[]}],"createdAt":100}]}"#, "診斷 v1 空白合法", expectedCount: 0)
    }

    private static func expectMalformedFixture(_ json: String, _ name: String, expectedCount: Int? = nil) throws {
        let file = try makeDirectory().appendingPathComponent("diagnostic.json")
        let bytes = Data(json.utf8)
        try bytes.write(to: file)
        if let expectedCount {
            let store = try CangjieSavedListStore(fileURL: file)
            try expect((try Data(contentsOf: file)) == bytes, "\(name) 保留原檔")
            try expect(store.entries.count == expectedCount, "\(name) 載入結果")
        } else {
            do {
                _ = try CangjieSavedListStore(fileURL: file)
                throw TestFailure(name: "\(name) 必須拒絕")
            } catch CangjieSavedListError.storeMalformed {
                try expect((try Data(contentsOf: file)) == bytes, "\(name) 拒絕後保留原檔")
            }
        }
    }

    private static func makeDirectory() throws -> URL {
        guard let root = ProcessInfo.processInfo.environment["CANGJIE_TEST_ROOT"] else {
            throw TestFailure(name: "缺少測試暫存目錄")
        }
        let path = URL(fileURLWithPath: root).appendingPathComponent("cangjie-model-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }
}
