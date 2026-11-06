import Cocoa

private enum Trace {
    static var events: [String] = []

    static func reset() {
        events = []
        NSWorkspace.shared.frontmostPID = 900
        NSApp.isActive = true
        NSRunningApplication.states = [42: AppState()]
        PasteboardHelper.contents = "原剪貼簿"
        PasteboardHelper.version = 1
    }
}

final class AppState {
    var isTerminated = false
    var activationAllowed = true
}

final class NSRunningApplication {
    static var states: [pid_t: AppState] = [:]
    let processIdentifier: pid_t

    init?(processIdentifier: pid_t) {
        guard Self.states[processIdentifier] != nil else { return nil }
        self.processIdentifier = processIdentifier
    }

    var isTerminated: Bool { Self.states[processIdentifier]?.isTerminated ?? true }

    func activate(options: NSApplication.ActivationOptions) -> Bool {
        Trace.events.append("activate")
        return Self.states[processIdentifier]?.activationAllowed == true
    }
}

final class FakeApplication {
    var isActive = true
}

let NSApp = FakeApplication()

final class NSWorkspace {
    static let shared = NSWorkspace()
    var frontmostPID: pid_t?
    var frontmostApplication: NSRunningApplication? {
        guard let frontmostPID else { return nil }
        return NSRunningApplication(processIdentifier: frontmostPID)
    }
}

struct PasteboardSnapshot {
    let contents: String
    let isComplete = true
}

struct PasteboardWriteResult {
    let didSetString = true
    let readbackMatches = true
    let changeCount: Int
}

final class PasteboardHelper {
    static var contents = "原剪貼簿"
    static var version = 1

    func makeSnapshot() -> PasteboardSnapshot { PasteboardSnapshot(contents: Self.contents) }

    func write(text: String) -> PasteboardWriteResult {
        Self.contents = text
        Self.version += 1
        Trace.events.append("write")
        return PasteboardWriteResult(changeCount: Self.version)
    }

    func contains(text: String) -> Bool { Self.contents == text }
    var changeCount: Int { Self.version }

    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        Self.contents = snapshot.contents
        Self.version += 1
        Trace.events.append("restore")
        return true
    }
}

struct FakeEventFlags: OptionSet {
    let rawValue: Int
    static let maskCommand = FakeEventFlags(rawValue: 1)
}

enum FakeTap {
    case cghidEventTap
}

final class CGEvent {
    var flags: FakeEventFlags = []
    private let isDown: Bool

    init?(keyboardEventSource: Any?, virtualKey: CGKeyCode, keyDown: Bool) {
        guard virtualKey == 9 else { return nil }
        isDown = keyDown
    }

    func post(tap: FakeTap) {
        Trace.events.append(isDown ? "pasteDown" : "pasteUp")
    }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("FAIL：\(message)，事件：\(Trace.events)")
    }
}

private func pause(_ milliseconds: Int) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
}

private func resultName(_ result: InjectionResult) -> String {
    switch result {
    case .dispatchedUnconfirmed: return "已分派"
    case .recoverableFailure(let reason): return "可重試：\(reason.rawValue)"
    case .orphaned(let reason): return "孤立：\(reason.rawValue)"
    case .busyRejected: return "忙碌"
    }
}

@main
private struct Runner {
    @MainActor static func main() async {
        await testWaitForConfirmedActivation()
        await testActivationRejection()
        await testTargetTermination()
        await testTimeout()
        await testFrontmostChangedDuringCallback()
        await testSelfReactivatedDuringCallback()
        print("PASS：焦點交接送出測試全部通過")
    }

    @MainActor private static func testWaitForConfirmedActivation() async {
        Trace.reset()
        let injector = TextInjector()
        var callbackCount = 0
        var results: [String] = []
        injector.inject(text: "測試", targetPID: 42, keepSubmittedText: false, onTargetActivated: {
            callbackCount += 1
            Trace.events.append("hide")
        }, completion: { results.append(resultName($0)) })

        expect(Trace.events == ["write", "activate"], "送出後仍在前景時不應隱藏或貼上")
        NSWorkspace.shared.frontmostPID = 42
        await pause(100)
        expect(callbackCount == 0, "即使目標 PID 已在前景，自己仍 active 時不應隱藏")
        expect(!Trace.events.contains("pasteDown"), "未完成焦點交接時不可貼上")

        NSApp.isActive = false
        await pause(100)
        expect(callbackCount == 1, "焦點確認後應隱藏一次")
        expect(Array(Trace.events.prefix(5)) == ["write", "activate", "hide", "pasteDown", "pasteUp"], "須先隱藏再貼上")
        injector.inject(text: "第二筆", targetPID: 42, keepSubmittedText: false, onTargetActivated: {
            fatalError("FAIL：忙碌時不應啟動第二筆")
        }, completion: { results.append(resultName($0)) })
        expect(results == ["忙碌"], "穩定窗口應阻擋第二次送出")
        expect(Trace.events.filter { $0 == "write" }.count == 1, "第二次送出不得覆蓋剪貼簿")
        await pause(1_050)
        expect(results == ["忙碌", "已分派"], "首次送出應完整結束")
        expect(PasteboardHelper.contents == "原剪貼簿", "已分派後應還原原剪貼簿")
        print("PASS：等待焦點、交接順序與重入")
    }

    @MainActor private static func testActivationRejection() async {
        Trace.reset()
        NSRunningApplication.states[42]?.activationAllowed = false
        var callbackCount = 0
        var results: [String] = []
        TextInjector().inject(text: "測試", targetPID: 42, keepSubmittedText: false,
                              onTargetActivated: { callbackCount += 1 },
                              completion: { results.append(resultName($0)) })
        expect(callbackCount == 0, "啟用被拒不得隱藏")
        expect(results == ["可重試：activationRejected"], "啟用被拒應可重試")
        expect(!Trace.events.contains("pasteDown"), "啟用被拒不可貼上")
        print("PASS：啟用被拒")
    }

    @MainActor private static func testTargetTermination() async {
        Trace.reset()
        let injector = TextInjector()
        var callbackCount = 0
        var results: [String] = []
        injector.inject(text: "測試", targetPID: 42, keepSubmittedText: false,
                        onTargetActivated: { callbackCount += 1 },
                        completion: { results.append(resultName($0)) })
        NSRunningApplication.states[42]?.isTerminated = true
        await pause(90)
        expect(callbackCount == 0, "目標結束不得隱藏")
        expect(results == ["孤立：targetTerminated"], "目標結束應標為孤立")
        expect(!Trace.events.contains("pasteDown"), "目標結束不可貼上")
        print("PASS：等待期間目標結束")
    }

    @MainActor private static func testTimeout() async {
        Trace.reset()
        let injector = TextInjector()
        var callbackCount = 0
        var results: [String] = []
        injector.inject(text: "測試", targetPID: 42, keepSubmittedText: false,
                        onTargetActivated: { callbackCount += 1 },
                        completion: { results.append(resultName($0)) })
        await pause(1_600)
        expect(callbackCount == 0, "逾時不得隱藏")
        expect(results == ["可重試：frontmostTimeout"], "逾時應可重試")
        expect(!Trace.events.contains("pasteDown"), "逾時不可貼上")
        print("PASS：前景切換逾時")
    }

    @MainActor private static func testFrontmostChangedDuringCallback() async {
        Trace.reset()
        NSWorkspace.shared.frontmostPID = 42
        NSApp.isActive = false
        let injector = TextInjector()
        var callbackCount = 0
        var results: [String] = []
        injector.inject(text: "測試", targetPID: 42, keepSubmittedText: false,
                        onTargetActivated: {
                            callbackCount += 1
                            NSWorkspace.shared.frontmostPID = 900
                        }, completion: { results.append(resultName($0)) })
        expect(callbackCount == 1, "確認前景後回呼應執行一次")
        expect(results == ["可重試：frontmostTimeout"], "回呼後前景改變應中止")
        expect(!Trace.events.contains("pasteDown"), "回呼後前景改變不可貼錯 App")
        print("PASS：隱藏回呼後前景改變")
    }

    @MainActor private static func testSelfReactivatedDuringCallback() async {
        Trace.reset()
        NSWorkspace.shared.frontmostPID = 42
        NSApp.isActive = false
        let injector = TextInjector()
        var callbackCount = 0
        var results: [String] = []
        injector.inject(text: "測試", targetPID: 42, keepSubmittedText: false,
                        onTargetActivated: {
                            callbackCount += 1
                            NSApp.isActive = true
                        }, completion: { results.append(resultName($0)) })
        expect(callbackCount == 1, "確認前景後回呼應執行一次")
        expect(results == ["可重試：frontmostTimeout"], "回呼後自己重新 active 應中止")
        expect(!Trace.events.contains("pasteDown"), "自己重新 active 時不可貼上")
        print("PASS：隱藏回呼後自己重新取得焦點")
    }
}
