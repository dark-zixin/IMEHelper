import Cocoa

private struct Failure: Error { let message: String }

@MainActor
private func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try value() else { throw Failure(message: message) }
}

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
}

@MainActor
@main
struct CangjieUITestRunner {
    static func main() {
        do {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            try run()
            try expect(NSApp.windows.allSatisfy { !$0.isVisible }, "元件測試不得顯示視窗")
            print("PASS：倉頡原生元件與離線畫面驗證")
        } catch let error as Failure {
            fputs("FAIL：\(error.message)\n", stderr)
            exit(1)
        } catch {
            fputs("FAIL：元件測試未預期錯誤\n", stderr)
            exit(1)
        }
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    private static func find<T: NSView>(_ id: String, in view: NSView, as type: T.Type = T.self) throws -> T {
        guard let found = descendants(view).first(where: { $0.identifier?.rawValue == id }) as? T else {
            throw Failure(message: "控制項未掛載：\(id)")
        }
        return found
    }

    private static func tap(_ id: String, _ view: NSView) throws {
        let button: NSButton = try find(id, in: view)
        button.performClick(nil)
        view.layoutSubtreeIfNeeded()
    }

    private static func input(_ value: String, _ controller: CangjieLookupWindowController) {
        let editor = controller.lookupView.input
        if editor.hasMarkedText() { editor.unmarkText() }
        editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        controller.lookupView.layoutSubtreeIfNeeded()
    }

    private static func size(_ controller: CangjieLookupWindowController, _ width: CGFloat, _ height: CGFloat, _ label: String) throws {
        guard let window = controller.window else { throw Failure(message: "缺少查碼窗") }
        try expect(abs(window.frame.width - width) <= 0.5 && abs(window.frame.height - height) <= 0.5,
                   "\(label) 尺寸應為 \(width)×\(height)，實際 \(window.frame.width)×\(window.frame.height)")
    }

    private static func capture(_ controller: CangjieLookupWindowController, to url: URL) throws {
        let view = controller.lookupView
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "無法建立離線畫面") }
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        guard let png = rep.representation(using: .png, properties: [:]) else { throw Failure(message: "無法編碼離線畫面") }
        try png.write(to: url)
    }

    private static func validateRows(_ view: NSView) throws {
        for item in descendants(view) {
            guard let parent = item.superview, let id = item.identifier?.rawValue,
                  id.hasSuffix("-roots"), !parent.isHidden else { continue }
            try expect(item.frame.minX >= 0 && item.frame.maxX <= parent.bounds.width + 0.5 && item.frame.maxY <= parent.bounds.height + 0.5,
                       "字根不能超出自己的列：\(id)")
            if let roots = item as? NSTextView, let manager = roots.layoutManager, let container = roots.textContainer {
                manager.ensureLayout(for: container)
                let used = manager.usedRect(for: container)
                try expect(used.width <= roots.bounds.width + 0.5 && used.height <= roots.bounds.height + 0.5,
                           "字根 glyph 必須落在可視列內：\(id)")
            }
        }
    }

    private static func scrollToBottom(_ scroll: NSScrollView, _ message: String) throws {
        guard let document = scroll.documentView else { throw Failure(message: "缺少捲動內容：\(message)") }
        let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
        try expect(bottom > 0, "\(message) 內容須超出可視區")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        scroll.reflectScrolledClipView(scroll.contentView)
        try expect(abs(scroll.contentView.bounds.minY - bottom) <= 0.5, "\(message) 必須可捲到底")
    }

    private static func run() throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { throw Failure(message: "需要專案、app bundle、測試輸出目錄") }
        let project = URL(fileURLWithPath: args[1])
        let appURL = URL(fileURLWithPath: args[2])
        let output = URL(fileURLWithPath: args[3])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let bundle = Bundle(url: appURL) else { throw Failure(message: "找不到真 app bundle") }
        let dictionary = try CangjieDictionary.load(bundle: bundle)
        let suite = output.appendingPathComponent("run-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: suite, withIntermediateDirectories: true)
        for locale in ["zh-Hant", "en"] {
            guard let language = Bundle(path: appURL.appendingPathComponent("Contents/Resources/\(locale).lproj").path) else { throw Failure(message: "缺語系bundle") }
            let localize: (String) -> String = { language.localizedString(forKey: $0, value: nil, table: nil) }
            try expect(localize("lookup.manage") == (locale == "en" ? "Manage" : "管理"), "測試必須切到指定語系")
            for (mode, name) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                let file = suite.appendingPathComponent("\(locale)-\(mode).json")
                let store = try CangjieSavedListStore(fileURL: file)
                for result in dictionary.lookup("具在曰晷慢念忙誠聽認字學語讀書寫記問答思看說話").reversed() { try store.save(result) }
                let defaults = MemoryDefaults()
                let controller = CangjieLookupWindowController(defaults: defaults, dictionaryLoader: { dictionary }, storeLoader: { store }, localize: localize)
                let view = controller.lookupView
                view.appearance = NSAppearance(named: name)
                controller.window?.appearance = NSAppearance(named: name)
                try expect(view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name, "外觀條件必須生效")
                input("曰", controller)
                try size(controller, 244, 138, "一字收合")
                let root: NSTextView = try find("query-0-roots", in: view)
                try expect(root.string == "日／難日", "只顯示完整中文字根")
                try capture(controller, to: output.appendingPathComponent("native_one_desktop_\(locale)_\(mode).png"))
                input("具在曰", controller)
                try size(controller, 244, 198, "三字收合")
                try capture(controller, to: output.appendingPathComponent("native_three_desktop_\(locale)_\(mode).png"))
                try tap("query-1-action", view)
                try expect(try CangjieSavedListStore(fileURL: file).entries.first?.character == "在", "逐字存按鈕接上真儲存入口")
                let savedButton: NSButton = try find("query-1-action", in: view)
                try expect(savedButton.title == localize("lookup.saved_short"), "保存成功立即顯示 Saved")
                try expect((savedButton.cell?.cellSize.width ?? .infinity) <= savedButton.frame.width + 0.5,
                           "保存成功按鈕 cell 不可裁切")
                try expect((savedButton.title as NSString).size(withAttributes: [.font: savedButton.font ?? NSFont.systemFont(ofSize: 12)]).width <= savedButton.frame.width + 0.5,
                           "保存成功文字不可裁切")
                try expect(savedButton.accessibilityLabel() == String(format: localize("lookup.saved_character"), "在"), "保存成功朗讀標籤")
                try capture(controller, to: output.appendingPathComponent("native_saved_\(locale)_\(mode).png"))
                try expect(store.entries.count == 23, "重存不增加字數")
                try tap("query-0-action", view)
                input("曰", controller)
                let resetButton: NSButton = try find("query-0-action", in: view)
                try expect(resetButton.title == localize("lookup.save") && store.entries.count == 23, "輸入改變後回 Save 且保存資料仍在")
                let top = controller.window!.frame.maxY
                try tap("cangjie-saved-toggle", view)
                try size(controller, 244, 332, "展開已存區")
                try expect(abs(controller.window!.frame.maxY - top) <= 0.5, "展開維持視窗上緣")
                let other: NSScrollView = try find("cangjie-other", in: view)
                try expect(other.frame.height == 60 && other.documentView!.frame.height > 60, "其他區固定兩列且其餘可捲動")
                let recent: NSScrollView = try find("cangjie-recent", in: view)
                try expect(recent.documentView!.subviews.filter { $0.identifier?.rawValue.hasPrefix("recent-") == true }.count == 3, "近期內容恰有三列")
                let otherButtons = other.documentView!.subviews.filter { $0.identifier?.rawValue.hasPrefix("other-") == true }.sorted { $0.frame.minY < $1.frame.minY || ($0.frame.minY == $1.frame.minY && $0.frame.minX < $1.frame.minX) }
                try expect(otherButtons.count >= 6 && otherButtons.prefix(5).allSatisfy { abs($0.frame.minY - otherButtons[0].frame.minY) <= 0.5 } && otherButtons[5].frame.minY > otherButtons[0].frame.minY,
                           "其他區前五個同列且第六個換行")
                other.contentView.scroll(to: NSPoint(x: 0, y: 60))
                other.reflectScrolledClipView(other.contentView)
                try expect(other.contentView.bounds.minY == 60, "其他區捲動能到後兩列")
                other.contentView.scroll(to: .zero)
                try capture(controller, to: output.appendingPathComponent("native_expanded_desktop_\(locale)_\(mode).png"))
                let gui = store.entries.first { $0.character == "晷" }!
                try tap("other-\(gui.id.uuidString)", view)
                try size(controller, 244, 372, "點選其他字")
                let detail: NSTextView = try find("selected-roots", in: view)
                try expect(detail.string == "日竹人口\n日竹卜口", "選字保留全部一般碼")
                try capture(controller, to: output.appendingPathComponent("native_selected_desktop_\(locale)_\(mode).png"))
                try tap("cangjie-manage", view)
                try tap("other-\(gui.id.uuidString)", view)
                try size(controller, 244, 372, "刪除確認不擴窗")
                try capture(controller, to: output.appendingPathComponent("native_confirm_desktop_\(locale)_\(mode).png"))
                let before = try Data(contentsOf: file)
                try tap("cangjie-cancel-delete", view)
                try expect(try Data(contentsOf: file) == before, "取消刪除不寫檔")
                try tap("other-\(gui.id.uuidString)", view)
                try tap("cangjie-confirm-delete", view)
                try expect(!store.entries.contains { $0.id == gui.id }, "確認刪除接上真儲存入口")
                try expect(try CangjieSavedListStore(fileURL: file).entries.count == 22, "刪後新實例看到結果")
                let recentID = store.entries[0].id
                try tap("recent-\(recentID.uuidString)-action", view)
                try tap("cangjie-confirm-delete", view)
                try expect(!store.entries.contains { $0.id == recentID }, "近期字的刪除入口可用")
                try tap("cangjie-manage", view)
                try tap("cangjie-saved-toggle", view)
                input("牑", controller)
                let manyRoots: NSTextView = try find("query-0-roots", in: view)
                try expect(manyRoots.string.components(separatedBy: "\n").count == 8, "八組碼全部保留")
                let results: NSScrollView = try find("cangjie-results", in: view)
                try expect(results.documentView!.frame.height > results.frame.height, "長碼可以捲動看完")
                try scrollToBottom(results, "長碼結果")
                try validateRows(view)
                try compositionTest(controller: controller, store: store)
                input("曰", controller)
                let beforeResizeTop = controller.window!.frame.maxY
                var frame = controller.window!.frame
                frame.size.width = 300
                frame.size.height += 20
                frame.origin.y = beforeResizeTop - frame.height
                controller.window!.setFrame(frame, display: false)
                controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: controller.window))
                let resizedTop = controller.window!.frame.maxY
                try tap("cangjie-saved-toggle", view)
                try expect(abs(controller.window!.frame.maxY - resizedTop) <= 0.5, "縮放後展開仍維持上緣")
                try tap("cangjie-pin", view)
                try expect(controller.window!.level == .floating && defaults.bool(forKey: "CangjieLookupWindowPinned"), "置頂按鈕與偏好接線")
                controller.window?.close()
                let reopened = CangjieLookupWindowController(defaults: defaults, dictionaryLoader: { dictionary }, storeLoader: { store }, localize: localize)
                try size(reopened, 300, 352, "重建視窗還原大小與展開狀態")
                try expect(reopened.window!.level == .floating && reopened.lookupView.isExpanded, "重建視窗還原置頂與展開")
                try expect(abs(reopened.window!.frame.maxY - resizedTop) <= 0.5, "重建視窗還原位置")
                reopened.window?.close()
                let legacyDefaults = MemoryDefaults()
                legacyDefaults.set(NSStringFromRect(NSRect(x: controller.window!.frame.minX, y: resizedTop - 540, width: 460, height: 540)), forKey: "CangjieLookupWindowFrame")
                let legacy = CangjieLookupWindowController(defaults: legacyDefaults, dictionaryLoader: { dictionary }, storeLoader: { store }, localize: localize)
                try size(legacy, 244, 138, "舊偏好不帶回大視窗")
                try expect(abs(legacy.window!.frame.maxY - resizedTop) <= 0.5, "承接舊視窗上緣位置")
                legacy.window?.close()
            }
        }
        try failureTest(dictionary: dictionary, appURL: appURL, output: suite)
        try savedScrollTest(dictionary: dictionary, output: suite)
        try anchorTest(dictionary: dictionary, output: suite)
        try shortcutTest(dictionary: dictionary, output: suite)
        print("PASS：四個基準尺寸、兩語淺深色、捲動、單字存刪、組字與縮放")
        _ = project
    }

    private static func compositionTest(controller: CangjieLookupWindowController, store: CangjieSavedListStore) throws {
        let view = controller.lookupView
        input("", controller)
        try size(controller, 244, 138, "空輸入收合")
        view.input.setMarkedText("hqi", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: 0))
        try expect(view.input.hasMarkedText(), "空框組字確實有 marked text")
        try expect(!descendants(view).contains { $0.identifier?.rawValue == "query-0" }, "空框組字不得建結果列")
        try size(controller, 244, 138, "空框組字不伸高")
        view.input.insertText("我", replacementRange: NSRange(location: NSNotFound, length: 0))
        let committed: NSTextView = try find("query-0-roots", in: view)
        let committedRoots = committed.string
        try expect(committedRoots.contains("竹手戈"), "組字提交後顯示我根")
        try size(controller, 244, 138, "單字提交收合")
        view.input.setMarkedText("hqi", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: view.input.string.utf16.count))
        let frozen: NSTextView = try find("query-0-roots", in: view)
        try expect(frozen.string == committedRoots, "替換組字保留既有我根")
        try size(controller, 244, 138, "替換組字保留高度")
        let save: NSButton = try find("query-0-action", in: view)
        try expect(!save.isEnabled, "組字期間停用保存")
        let before = store.entries
        if let action = save.action { NSApp.sendAction(action, to: save.target, from: save) }
        try expect(store.entries == before, "組字保存guard不可繞過")
        view.input.insertText("日", replacementRange: NSRange(location: NSNotFound, length: 0))
        let updated: NSTextView = try find("query-0-roots", in: view)
        try expect(updated.string == "日", "替換組字提交後更新日根")
        view.input.setMarkedText("hqi", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: 0, length: view.input.string.utf16.count))
        view.input.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.input.unmarkText()
        try expect(view.input.string.isEmpty && !descendants(view).contains { $0.identifier?.rawValue == "query-0" }, "組字取消清空後移除結果列")
        try size(controller, 244, 138, "組字取消後收合")
    }

    private static func savedScrollTest(dictionary: CangjieDictionary, output: URL) throws {
        let store = try CangjieSavedListStore(fileURL: output.appendingPathComponent("saved-scroll.json"))
        _ = try store.save(CangjieCharacterResult(character: "月", codes: ["b"]))
        _ = try store.save(CangjieCharacterResult(character: "日", codes: ["a"]))
        let page = try store.save(CangjieCharacterResult(character: "版", codes: ["llhe", "lnhe", "xlnhe"]))
        let controller = CangjieLookupWindowController(defaults: MemoryDefaults(), dictionaryLoader: { dictionary }, storeLoader: { store }, localize: { $0 })
        let view = controller.lookupView
        try tap("cangjie-saved-toggle", view)
        let recent: NSScrollView = try find("cangjie-recent", in: view)
        try expect(recent.documentView!.subviews.filter { $0.identifier?.rawValue.hasPrefix("recent-") == true }.count == 3, "三字近期恰有三列")
        try scrollToBottom(recent, "近期第三列")
        _ = try store.save(CangjieCharacterResult(character: "具", codes: ["bmmc"]))
        _ = try store.save(CangjieCharacterResult(character: "在", codes: ["klg"]))
        _ = try store.save(CangjieCharacterResult(character: "曰", codes: ["a"]))
        view.setResources(dictionary: dictionary, store: store, resourceIssue: nil, storeIssue: nil)
        try tap("other-\(page.id.uuidString)", view)
        let detail: NSScrollView = try find("cangjie-detail", in: view)
        let roots: NSTextView = try find("selected-roots", in: view)
        try expect(roots.string.components(separatedBy: "\n").count == 3, "詳情保留版的三組碼")
        try scrollToBottom(detail, "詳情第三碼")
        controller.window?.close()
    }

    private static func anchorTest(dictionary: CangjieDictionary, output: URL) throws {
        let store = try CangjieSavedListStore(fileURL: output.appendingPathComponent("anchor.json"))
        let defaults = MemoryDefaults()
        let anchor = NSPoint(x: 756, y: 138)
        defaults.set(NSStringFromPoint(anchor), forKey: "CangjieLookupManualTopLeft")
        var frames = [NSRect(x: 0, y: 0, width: 1000, height: 800)]
        do {
            let controller = CangjieLookupWindowController(defaults: defaults, dictionaryLoader: { dictionary }, storeLoader: { store }, visibleFrames: { frames }, localize: { $0 })
            let view = controller.lookupView
            try expect(abs(controller.window!.frame.minX - 756) <= 0.5 && abs(controller.window!.frame.minY) <= 0.5, "手動錨點初始位置")
            try tap("cangjie-saved-toggle", view)
            try size(controller, 244, 332, "下緣展開夾回")
            try expect(abs(controller.window!.frame.minY) <= 0.5, "展開後下緣夾回")
            controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: controller.window))
            controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: controller.window))
            try expect(defaults.string(forKey: "CangjieLookupManualTopLeft") == NSStringFromPoint(anchor), "夾回不得覆寫手動錨點")
            try tap("cangjie-saved-toggle", view)
            try size(controller, 244, 138, "下緣收合復位")
            try expect(abs(controller.window!.frame.minY) <= 0.5 && defaults.string(forKey: "CangjieLookupManualTopLeft") == NSStringFromPoint(anchor), "縮回應回手動位置")
            input("具在曰", controller)
            try size(controller, 244, 198, "多字展開")
            input("曰", controller)
            try size(controller, 244, 138, "多字縮回")
            try expect(abs(controller.window!.frame.minY) <= 0.5, "多字展收後復位")
            try tap("cangjie-saved-toggle", view)
            controller.window!.setFrame(NSRect(x: 100, y: 200, width: 244, height: 332), display: false)
            controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: controller.window))
            try tap("cangjie-saved-toggle", view)
            try expect(abs(controller.window!.frame.minY - 394) <= 0.5 && abs(controller.window!.frame.maxY - 532) <= 0.5, "手動搬動後收合保留上緣")
            controller.window!.setFrame(NSRect(x: 100, y: 374, width: 300, height: 158), display: false)
            controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: controller.window))
            try size(controller, 300, 158, "手動縮放寬度與額外高度")
            controller.window!.setFrame(NSRect(x: 100, y: 374, width: 500, height: 158), display: false)
            controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: controller.window))
            try size(controller, 500, 158, "手動改寬至五百")
            frames = [NSRect(x: 0, y: 0, width: 400, height: 400)]
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            try expect(controller.window!.frame.maxX <= 400.5 && controller.window!.frame.maxY <= 400.5, "模擬螢幕移除後夾回")
            try size(controller, 400, 158, "窄螢幕只夾目前寬")
            try expect(defaults.double(forKey: "CangjieLookupCompactWidth") == 500, "夾回不得覆寫手動寬度偏好")
            try expect(defaults.string(forKey: "CangjieLookupManualTopLeft") == NSStringFromPoint(NSPoint(x: 100, y: 532)), "螢幕夾回不改手動錨點")
            controller.window?.close()
        }
        do {
            let clamped = CangjieLookupWindowController(defaults: defaults, dictionaryLoader: { dictionary }, storeLoader: { store }, visibleFrames: { frames }, localize: { $0 })
            try size(clamped, 400, 158, "夾回狀態重建仍受窄螢幕限制")
            try expect(defaults.double(forKey: "CangjieLookupCompactWidth") == 500, "夾回重建仍保存手動寬度")
            frames = [NSRect(x: 0, y: 0, width: 1000, height: 800)]
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            try size(clamped, 500, 158, "螢幕復原後恢復手動寬度")
            try expect(abs(clamped.window!.frame.maxY - 532) <= 0.5, "螢幕復原後回手動位置")
            clamped.window?.close()
        }
        let reopened = CangjieLookupWindowController(defaults: defaults, dictionaryLoader: { dictionary }, storeLoader: { store }, visibleFrames: { frames }, localize: { $0 })
        try size(reopened, 500, 158, "重建還原手動縮放")
        try expect(abs(reopened.window!.frame.minX - 100) <= 0.5 && abs(reopened.window!.frame.maxY - 532) <= 0.5, "重建還原手動位置")
        reopened.window?.close()
        let invalid = MemoryDefaults()
        invalid.set("{1e309, 0}", forKey: "CangjieLookupManualTopLeft")
        let fallback = CangjieLookupWindowController(defaults: invalid, dictionaryLoader: { dictionary }, storeLoader: { store }, visibleFrames: { frames }, localize: { $0 })
        try expect(fallback.window!.frame.minX.isFinite && fallback.window!.frame.minY.isFinite, "非法錨點偏好退回有限位置")
        fallback.window?.close()
    }

    private static func shortcutTest(dictionary: CangjieDictionary, output: URL) throws {
        let store = try CangjieSavedListStore(fileURL: output.appendingPathComponent("paste.json"))
        let controller = CangjieLookupWindowController(defaults: MemoryDefaults(), dictionaryLoader: { dictionary }, storeLoader: { store }, localize: { $0 })
        let editor = controller.lookupView.input
        // 只呼叫元件的按鍵入口，不送系統事件；剪貼簿內容在記憶體暫存後還原。
        let clipboard = NSPasteboard.general
        let saved = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in item.data(forType: type).map { (type, $0) } }
        }
        defer {
            clipboard.clearContents()
            let items = saved.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { clipboard.writeObjects(items) }
        }
        clipboard.clearContents()
        try expect(clipboard.setString("具在曰", forType: .string), "測試環境必須能寫入剪貼簿")
        try expect(clipboard.string(forType: .string) == "具在曰", "測試環境必須能讀回剪貼簿")
        controller.window?.makeFirstResponder(editor)
        let paste = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "v", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)!
        try expect(editor.performKeyEquivalent(with: paste), "專用文字元件必須接住CmdV")
        try expect(editor.string == "具在曰", "CmdV應實際貼入三字")
        let root: NSTextView = try find("query-0-roots", in: controller.lookupView)
        try expect(root.string == "月一一金", "貼上後真delegate更新字根")
        controller.window?.makeFirstResponder(root)
        root.setSelectedRange(NSRange(location: 0, length: root.string.utf16.count))
        let copy = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        try expect(!editor.performKeyEquivalent(with: copy), "未聚焦輸入框不能攔走字根的複製")
        try expect(root.performKeyEquivalent(with: copy), "字根元件必須接住CmdC")
        try expect(clipboard.string(forType: .string) == "月一一金", "CmdC應複製目前選取字根")
        controller.window?.makeFirstResponder(editor)
        editor.undoManager?.removeAllActions()
        editor.breakUndoCoalescing()
        let selectAll = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        try expect(editor.performKeyEquivalent(with: selectAll), "專用文字元件必須接住CmdA")
        try expect(editor.selectedRange() == NSRange(location: 0, length: 3), "CmdA 應全選三字")
        let cut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7)!
        try expect(editor.performKeyEquivalent(with: cut), "專用文字元件必須接住CmdX")
        try expect(editor.string.isEmpty && clipboard.string(forType: .string) == "具在曰", "CmdX 應剪下選字")
        try expect(!descendants(controller.lookupView).contains { $0.identifier?.rawValue == "query-0" }, "剪下後查碼列清空")
        let undo = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        try expect(editor.performKeyEquivalent(with: undo), "專用文字元件必須接住CmdZ")
        try expect(editor.string == "具在曰", "CmdZ 應復原文字")
        let undoSelection = editor.selectedRange()
        try expect(undoSelection.location != NSNotFound && undoSelection.location + undoSelection.length <= editor.string.utf16.count,
                   "CmdZ 後選區須位於復原文字內")
        let restoredRoots: NSTextView = try find("query-0-roots", in: controller.lookupView)
        try expect(restoredRoots.string == "月一一金", "復原後查碼跟著更新")
        let redo = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0, windowNumber: controller.window!.windowNumber, context: nil, characters: "Z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6)!
        try expect(editor.performKeyEquivalent(with: redo), "專用文字元件必須接住CmdShiftZ")
        try expect(editor.string.isEmpty && editor.selectedRange() == NSRange(location: 0, length: 0), "CmdShiftZ 應重做剪下")
        try expect(!descendants(controller.lookupView).contains { $0.identifier?.rawValue == "query-0" }, "重做後查碼列清空")
        controller.window?.close()
    }

    private static func failureTest(dictionary: CangjieDictionary, appURL: URL, output: URL) throws {
        for locale in ["zh-Hant", "en"] {
            guard let language = Bundle(path: appURL.appendingPathComponent("Contents/Resources/\(locale).lproj").path),
                  let helpURL = language.url(forResource: "CangjieRecovery", withExtension: "html") else {
                throw Failure(message: "缺少 \(locale) 離線恢復說明")
            }
            try expect(FileManager.default.fileExists(atPath: helpURL.path), "恢復說明必須是本機 bundle 資源")
            let localize: (String) -> String = { language.localizedString(forKey: $0, value: nil, table: nil) }
            let corrupt = output.appendingPathComponent("corrupt-\(locale).json")
            try "{壞清單}".write(to: corrupt, atomically: true, encoding: .utf8)
            let usable = try CangjieSavedListStore(fileURL: output.appendingPathComponent("recovered-\(locale).json"))
            var loadFails = true
            var opened: URL?
            let failed = CangjieLookupWindowController(defaults: MemoryDefaults(), dictionaryLoader: { dictionary }, storeLoader: {
                if loadFails { return try CangjieSavedListStore(fileURL: corrupt) }
                return usable
            }, recoveryHelpURL: helpURL, openHelp: { url in opened = url; return true }, localize: localize)
            input("曰", failed)
            let view = failed.lookupView
            let save: NSButton = try find("query-0-action", in: view)
            let status: NSTextField = try find("cangjie-status", in: view)
            let disclosure: NSButton = try find("cangjie-saved-toggle", in: view)
            try expect(!save.isEnabled && status.stringValue == localize("lookup.load_error"), "清單讀錯仍可查碼但不能保存")
            try expect(disclosure.title.contains(localize("lookup.saved_unavailable")) && !disclosure.title.contains("0"), "未知清單不得顯示零筆")
            try tap("cangjie-saved-toggle", view)
            let emptySaved: NSTextField = try find("cangjie-empty-saved", in: view)
            let emptyOther: NSTextField = try find("cangjie-empty-other", in: view)
            try expect(emptySaved.stringValue == localize("lookup.saved_unavailable") && emptySaved.stringValue != localize("lookup.empty_saved") && emptyOther.isHidden,
                       "讀取失敗不得偽裝空清單")
            let retry: NSButton = try find("cangjie-retry", in: view)
            let help: NSButton = try find("cangjie-recovery-help", in: view)
            try expect(!retry.isHidden && retry.isEnabled && !help.isHidden && help.isEnabled && help.title == localize("lookup.recovery_help"), "失敗畫面提供重試及恢復說明")
            try capture(failed, to: output.appendingPathComponent("native_failure_\(locale).png"))
            try tap("cangjie-recovery-help", view)
            try expect(opened == helpURL, "恢復說明開啟正確的本機語系資源")
            let manage: NSButton = try find("cangjie-manage", in: view)
            try expect(!manage.isEnabled && manage.title == localize("lookup.manage"), "讀取失敗初始管理停用")
            // 只驗關窗清理後沿用同一實例的狀態，不顯示視窗或重建已存區。
            let retainedWindow = failed.window
            retainedWindow?.close()
            try expect(view.isExpanded && failed.window === retainedWindow, "關窗保留已展開的同一視窗實例")
            failed.window?.makeFirstResponder(view.input)
            view.layoutSubtreeIfNeeded()
            try expect(!manage.isEnabled && manage.title == localize("lookup.manage"), "讀取失敗關窗清理後管理仍停用")
            try tap("cangjie-manage", view)
            try expect(manage.title == localize("lookup.manage"), "停用管理不得切進管理模式")
            try tap("cangjie-retry", view)
            try expect(status.stringValue == localize("lookup.load_error") && usable.entries.isEmpty, "持續失敗重試保持未知狀態")
            try expect(!manage.isEnabled && manage.title == localize("lookup.manage"), "重試仍失敗時管理保持停用")
            loadFails = false
            try tap("cangjie-retry", view)
            try expect(disclosure.title.contains("0") && emptySaved.stringValue == localize("lookup.empty_saved") && !emptySaved.isHidden, "重試成功顯示真正零筆")
            let restoredSave: NSButton = try find("query-0-action", in: view)
            try expect(restoredSave.isEnabled && retry.isHidden && help.isHidden, "重試成功恢復保存入口")
            try expect(manage.isEnabled && manage.title == localize("lookup.manage"), "重試成功維持一般管理入口")
            try tap("query-0-action", view)
            try expect(usable.entries.count == 1, "重試成功後可以保存")
            let recoveredEntry = usable.entries[0]
            let deleteID = "recent-\(recoveredEntry.id.uuidString)-action"
            try expect(!descendants(view).contains { $0.identifier?.rawValue == deleteID }, "重試成功不會自行顯示刪除入口")
            try tap("cangjie-manage", view)
            let delete: NSButton = try find(deleteID, in: view)
            try expect(delete.isEnabled && manage.title == localize("lookup.done"), "重試成功後可正常進入管理")
            try tap("cangjie-manage", view)
            try expect(manage.title == localize("lookup.manage") && !descendants(view).contains { $0.identifier?.rawValue == deleteID }, "重試成功後可正常離開管理")
            failed.window?.close()

            for (label, missingURL, openResult) in [("缺資源", true, true), ("開啟失敗", false, false)] {
                var attempted = false
                let controller = CangjieLookupWindowController(defaults: MemoryDefaults(), dictionaryLoader: { dictionary }, storeLoader: { try CangjieSavedListStore(fileURL: corrupt) }, recoveryHelpURL: missingURL ? nil : helpURL, openHelp: { _ in attempted = true; return openResult }, localize: localize)
                try tap("cangjie-recovery-help", controller.lookupView)
                let error: NSTextField = try find("cangjie-status", in: controller.lookupView)
                let unknown: NSButton = try find("cangjie-saved-toggle", in: controller.lookupView)
                try expect(error.stringValue == localize("lookup.recovery_help_error") && unknown.title.contains(localize("lookup.saved_unavailable")), "\(label) 顯示說明錯誤且清單仍未知")
                try expect(attempted == !missingURL, "\(label) 開啟 closure 呼叫條件")
                controller.window?.close()
            }
            let missing = CangjieLookupWindowController(defaults: MemoryDefaults(), dictionaryLoader: { throw CangjieDictionaryError.resourceMissing }, storeLoader: { usable }, localize: localize)
            let dictionaryStatus: NSTextField = try find("cangjie-status", in: missing.lookupView)
            try expect(dictionaryStatus.stringValue == localize("lookup.dictionary_error"), "字典錯誤不偽裝未收錄")
            missing.window?.close()
            let blockedDirectory = output.appendingPathComponent("blocked-ui-\(locale)")
            try FileManager.default.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)
            let blockedStore = try CangjieSavedListStore(fileURL: blockedDirectory.appendingPathComponent("saved.json"))
            let blocked = CangjieLookupWindowController(defaults: MemoryDefaults(), dictionaryLoader: { dictionary }, storeLoader: { blockedStore }, localize: localize)
            input("具", blocked)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: blockedDirectory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockedDirectory.path) }
            try tap("query-0-action", blocked.lookupView)
            let writeStatus: NSTextField = try find("cangjie-status", in: blocked.lookupView)
            try expect(writeStatus.stringValue == localize("lookup.save_error") && blockedStore.entries.isEmpty, "保存失敗要顯示錯誤且不能假成功")
            blocked.window?.close()
        }
    }
}
