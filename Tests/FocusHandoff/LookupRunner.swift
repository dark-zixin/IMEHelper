import Cocoa

private struct Failure: Error { let message: String }

private final class MemoryDefaults: UserDefaults {
    private var values: [String: Any] = [:]
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func double(forKey key: String) -> Double { values[key] as? Double ?? 0 }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
}

private final class KeyboardProbe: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var enterCount = 0
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { enterCount += 1 }
    }
}

@main @MainActor
private struct Runner {
    static var retained: [AnyObject] = []
    static var output: URL!

    static func log(_ line: String) {
        let prior = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        try! (prior + line + "\n").write(to: output, atomically: true, encoding: .utf8)
    }

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        guard value() else { throw Failure(message: message) }
    }

    static func pause(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
    static func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { views($0) } }

    static func button(_ id: String, in view: NSView) throws -> NSButton {
        guard let button = views(view).first(where: { $0.identifier?.rawValue == id }) as? NSButton else {
            throw Failure(message: "找不到按鈕：\(id)")
        }
        return button
    }

    static func hasConfirmation(_ view: NSView) -> Bool {
        views(view).contains { $0.identifier?.rawValue == "cangjie-delete-confirmation" }
    }

    static func click(_ point: NSPoint, in window: NSWindow) async {
        for kind: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: kind == .leftMouseDown ? 1 : 0)!
            NSApp.postEvent(event, atStart: false)
        }
        await pause(150)
    }

    static func click(_ view: NSView) async {
        let point = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
        await click(point, in: view.window!)
    }

    static func key(_ code: UInt16, _ characters: String) async throws {
        guard let window = NSApp.keyWindow else { throw Failure(message: "沒有接收按鍵的視窗") }
        NSApp.postEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code)!, atStart: false)
        await pause(150)
    }

    static func run(appPath: String, coverPath: String) async throws {
        guard let bundle = Bundle(path: appPath) else { throw Failure(message: "缺少 app bundle") }
        let dictionary = try CangjieDictionary.load(bundle: bundle)
        let store = try CangjieSavedListStore(fileURL: output.deletingLastPathComponent().appendingPathComponent("saved-\(UUID().uuidString).json"))
        try store.save(dictionary.lookup("在")[0])
        let controller = CangjieLookupWindowController(defaults: MemoryDefaults(), dictionaryLoader: { dictionary }, storeLoader: { store })
        let lookup = controller.window!
        lookup.setFrameOrigin(NSPoint(x: 80, y: 200))
        let input = KeyboardProbe(contentRect: NSRect(x: 400, y: 200, width: 240, height: 120),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        input.title = "焦點測試：按鍵只計數，不送出文字"
        input.isReleasedWhenClosed = false
        input.level = .floating
        input.isFloatingPanel = true
        input.hidesOnDeactivate = false
        retained = [controller, input]
        defer { lookup.close(); input.close() }
        NSApp.activate(ignoringOtherApps: true)
        lookup.makeKeyAndOrderFront(nil)
        input.makeKeyAndOrderFront(nil)
        for _ in 0..<50 {
            if NSApp.isActive && input.isKeyWindow { break }
            await pause(100)
        }
        try expect(NSApp.isActive && input.isKeyWindow, "測試程序須實際在前景且輸入測試面板為 key")
        let view = controller.lookupView
        view.setExpanded(true)
        try button("cangjie-manage", in: view).performClick(nil)
        view.layoutSubtreeIfNeeded()
        let deleteID = "recent-\(store.entries[0].id.uuidString)-action"

        for (code, characters, name) in [(UInt16(36), "\r", "Enter"), (UInt16(53), "\u{1b}", "Esc")] {
            input.makeKeyAndOrderFront(nil)
            try expect(input.isKeyWindow && !lookup.isKeyWindow, "點擊前須由另一面板接收按鍵")
            await click(try button(deleteID, in: view))
            try expect(lookup.isKeyWindow, "點刪除按鈕後查碼窗必須接收鍵盤")
            // 焦點已由真滑鼠事件驗證；第一下若僅啟用視窗，再經控制項 action 開啟確認。
            if !hasConfirmation(view) { try button(deleteID, in: view).performClick(nil) }
            try expect(hasConfirmation(view), "點擊必須實際打開刪除確認")
            try await key(code, characters)
            try expect(!hasConfirmation(view) && lookup.isVisible, "\(name) 應取消確認並保留查碼窗")
            try expect(input.enterCount == 0 && store.entries.count == 1, "取消不得把 Enter 送到另一面板或刪除資料")
            log("PASS：點查碼刪除後 \(name) 取消，其他面板未收到 Enter")
        }

        for (name, point) in [("空白", NSPoint(x: 2, y: 2)), ("標題區", NSPoint(x: lookup.frame.width / 2, y: lookup.frame.height - 3))] {
            input.makeKeyAndOrderFront(nil)
            await click(point, in: lookup)
            try expect(lookup.isKeyWindow, "左鍵點\(name)後查碼窗必須接收鍵盤")
        }
        log("PASS：左鍵點空白與標題區取得查碼焦點")

        for action in ["隱藏", "關閉"] {
            lookup.makeKeyAndOrderFront(nil)
            lookup.makeFirstResponder(view.input)
            try expect(lookup.firstResponder === view.input, "查碼窗須保留真輸入框為第一回應者")
            input.makeKeyAndOrderFront(nil)
            await pause(100)
            try expect(NSApp.isActive && input.isKeyWindow && input.isMainWindow, "被動交接測試須在有效前景條件開始")
            if action == "隱藏" { input.orderOut(nil) } else { input.close() }
            var tookKey = false
            for _ in 0..<30 { tookKey = tookKey || lookup.isKeyWindow; await pause(10) }
            try expect(!tookKey, "輸入面板\(action)時查碼窗不得自動取得 key")
        }
        log("PASS：輸入測試面板隱藏與關閉時查碼窗不接任 key")

        lookup.makeKeyAndOrderFront(nil)
        lookup.makeFirstResponder(view.input)
        view.input.string = "測試草稿"
        try await key(53, "\u{1b}")
        try expect(lookup.isVisible && view.input.string == "測試草稿", "查碼輸入框 Esc 不得關窗或清空文字")
        log("PASS：查碼輸入框 Esc 保留視窗與文字")
        try button("cangjie-pin", in: view).performClick(nil)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.arguments = ["--cover"]
        let cover = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: coverPath), configuration: configuration)
        defer { cover.terminate() }
        await pause(200)
        log("INFO：失焦前 hidesOnDeactivate=\(lookup.hidesOnDeactivate)")
        NSApp.yieldActivation(to: cover)
        _ = cover.activate(from: .current, options: [])
        for _ in 0..<50 {
            if !NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == cover.processIdentifier { break }
            await pause(50)
        }
        try expect(!NSApp.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier == cover.processIdentifier,
                   "測試前提失敗：背景測試 App 未取得前景")
        await pause(250)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let remainsOnScreen = windows.contains { $0[kCGWindowNumber as String] as? Int == lookup.windowNumber }
        try expect(lookup.isVisible && remainsOnScreen, "置頂查碼窗必須在 App 失焦後繼續顯示")
        log("PASS：置頂查碼窗在 App 失焦後仍可見")
        log("PASS：查碼窗前景操作與被動焦點交接全部通過")
    }

    static func main() {
        if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--cover" {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let window = NSWindow(contentRect: NSRect(x: 650, y: 200, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "查碼焦點測試：背景程序"
            window.isReleasedWhenClosed = false
            retained = [window]
            window.orderFrontRegardless()
            DispatchQueue.global().asyncAfter(deadline: .now() + 15) { exit(0) }
            app.run()
            return
        }
        guard CommandLine.arguments.count == 4 else { exit(2) }
        output = URL(fileURLWithPath: CommandLine.arguments[2])
        try! "".write(to: output, atomically: true, encoding: .utf8)
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { @MainActor in
            do { try await run(appPath: CommandLine.arguments[1], coverPath: CommandLine.arguments[3]); exit(0) }
            catch let failure as Failure { log("FAIL：\(failure.message)"); exit(1) }
            catch { log("FAIL：原生查碼焦點測試錯誤 \(error)"); exit(1) }
        }
        // 事件追蹤或系統焦點無法完成時，不能留下測試視窗或假稱成功。
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) { exit(2) }
        app.run()
    }
}
