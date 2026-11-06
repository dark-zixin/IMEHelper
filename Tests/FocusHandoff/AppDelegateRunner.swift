import Cocoa

final class PanelManagerWindowController {
    static func show() {}
}

enum InjectionResult {
    case dispatchedUnconfirmed
    case recoverableFailure
    case orphaned
    case busyRejected
}

@MainActor
final class TextInjector {
    static var latest: TextInjector?
    private(set) var isActive = false
    private(set) var injectedText: String?
    private(set) var targetPID: pid_t?
    private(set) var onTargetActivated: (() -> Void)?
    private(set) var completion: ((InjectionResult) -> Void)?

    init() { Self.latest = self }

    func inject(text: String, targetPID: pid_t, keepSubmittedText: Bool,
                onTargetActivated: @escaping () -> Void,
                completion: @escaping (InjectionResult) -> Void) {
        isActive = true
        injectedText = text
        self.targetPID = targetPID
        self.onTargetActivated = onTargetActivated
        self.completion = completion
    }

    func prepareForTermination() {}
}

private final class CountingPanel: InputPanel {
    private(set) var hideCount = 0
    private(set) var showCount = 0
    private(set) var closeCount = 0

    override func orderOut(_ sender: Any?) {
        hideCount += 1
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        showCount += 1
    }

    override func hidePanel() {
        closeCount += 1
    }

    override func focusTextView() {}
}

private struct Failure: Error {
    let message: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw Failure(message: message) }
}

@MainActor
@main
private struct Runner {
    static func main() {
        do {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            NSApp.finishLaunching()
            try testSubmissionWiring()
            try testCompletionBranches()
            try expect(NSApp.windows.allSatisfy { !$0.isVisible }, "測試不應顯示視窗")
            print("PASS：AppDelegate 送出接線測試全部通過")
        } catch let error as Failure {
            fputs("FAIL：\(error.message)\n", stderr)
            exit(1)
        } catch {
            fputs("FAIL：未預期測試錯誤：\(error)\n", stderr)
            exit(1)
        }
    }

    private static func testSubmissionWiring() throws {
        guard let source = SourceAppInfo.fromApp(pid: getpid()) else {
            throw Failure(message: "無法取得測試程序的來源 App")
        }

        let panel = CountingPanel()
        defer { panel.close() }
        panel.setSourceApp(source)
        panel.text = "已提交草稿"
        let appDelegate = AppDelegate()

        appDelegate.inputPanelDidSubmit(panel, text: panel.text)

        guard let injector = TextInjector.latest else {
            throw Failure(message: "AppDelegate 未建立送出器")
        }
        try expect(injector.isActive, "送出入口應啟動交易")
        try expect(injector.injectedText == "已提交草稿", "送出內容應傳入交易")
        try expect(injector.targetPID == source.pid, "目標應是輸入面板原來源")
        try expect(panel.isInjecting, "等待焦點期間面板應鎖定")
        try expect(panel.hideCount == 0, "送出後、目標取得焦點前不可隱藏面板")

        guard let onTargetActivated = injector.onTargetActivated else {
            throw Failure(message: "送出入口未接上焦點確認回呼")
        }
        onTargetActivated()
        try expect(panel.hideCount == 1, "目標取得焦點後應隱藏面板一次")
        print("PASS：AppDelegate 真入口接線與延後隱藏")
    }

    private static func testCompletionBranches() throws {
        guard let source = SourceAppInfo.fromApp(pid: getpid()) else {
            throw Failure(message: "無法取得測試程序的來源 App")
        }

        let cases: [(name: String, result: InjectionResult, keepsText: Bool, orphaned: Bool, closes: Bool)] = [
            ("已分派", .dispatchedUnconfirmed, false, false, true),
            ("可重試", .recoverableFailure, true, false, false),
            ("目標結束", .orphaned, true, true, false),
            ("忙碌", .busyRejected, true, false, false),
        ]

        for item in cases {
            let panel = CountingPanel()
            defer { panel.close() }
            panel.setSourceApp(source)
            panel.text = "已提交草稿"
            let appDelegate = AppDelegate()
            appDelegate.inputPanelDidSubmit(panel, text: panel.text)
            guard let completion = TextInjector.latest?.completion else {
                throw Failure(message: "\(item.name) 缺少送出完成回呼")
            }

            completion(item.result)
            try expect(!panel.isInjecting, "\(item.name) 後面板應解除鎖定")
            try expect(item.keepsText ? panel.text == "已提交草稿" : panel.text.isEmpty,
                       "\(item.name) 後草稿保留或清空不符")
            try expect(panel.isOrphaned == item.orphaned, "\(item.name) 後孤立狀態不符")
            try expect((panel.closeCount == 1) == item.closes, "\(item.name) 後關閉狀態不符")
            try expect(panel.showCount == (item.closes ? 0 : 1), "\(item.name) 後面板顯示路徑不符")
            try expect(!panel.isVisible, "\(item.name) 不應顯示測試視窗")
            print("PASS：AppDelegate 完成分支 \(item.name)")
        }
    }
}
