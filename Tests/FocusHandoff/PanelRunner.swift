import Cocoa

final class SettingsWindowController {
    static var shared: SettingsWindowController?
    static let visibilityDidChangeNotification = Notification.Name("測試設定視窗顯示變化")
    func restoreColorWell() {}
}

private struct Failure: Error {
    let message: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw Failure(message: message) }
}

private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

private final class InputSpy: InputTextViewDelegate {
    var enterCount = 0
    var escapeCount = 0

    func inputTextViewDidPressEnter(_ textView: InputTextView) { enterCount += 1 }
    func inputTextViewDidPressEscape(_ textView: InputTextView) { escapeCount += 1 }
}

private func keyEvent(_ code: UInt16, characters: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                     windowNumber: 0, context: nil, characters: characters,
                     charactersIgnoringModifiers: characters, isARepeat: false,
                     keyCode: code)!
}

@MainActor
@main
private struct Runner {
    static func main() {
        do {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            try testPanelLockedDuringHandoff()
            try testEditorKeyGate()
            try expect(NSApp.windows.allSatisfy { !$0.isVisible }, "元件測試不可顯示視窗")
            print("PASS：輸入面板焦點等待測試全部通過")
        } catch let error as Failure {
            fputs("FAIL：\(error.message)\n", stderr)
            exit(1)
        } catch {
            fputs("FAIL：未預期測試錯誤\n", stderr)
            exit(1)
        }
    }

    private static func testPanelLockedDuringHandoff() throws {
        let panel = InputPanel()
        defer { panel.close() }
        guard let content = panel.contentView,
              let editor = descendants(content).compactMap({ $0 as? InputTextView }).first else {
            throw Failure(message: "找不到輸入面板的文字區")
        }

        panel.text = "已提交草稿"
        try expect(editor.isEditable, "送出前文字區應可編輯")
        panel.isInjecting = true
        try expect(!editor.isEditable, "等待焦點交接時文字區應鎖定")
        panel.inputTextViewDidPressEscape(editor)
        panel.inputTextViewDidPressEscape(editor)
        try expect(panel.text == "已提交草稿", "等待期間 ESC 不得清空草稿")
        try expect(!panel.windowShouldClose(panel), "等待期間使用者不得關閉面板")
        panel.isClosingProgrammatically = true
        try expect(panel.windowShouldClose(panel), "程式完成送出後仍應能關閉面板")
        panel.isClosingProgrammatically = false

        panel.isInjecting = false
        try expect(editor.isEditable, "失敗恢復後文字區應可編輯")
        panel.inputTextViewDidPressEscape(editor)
        panel.inputTextViewDidPressEscape(editor)
        try expect(panel.text.isEmpty, "解鎖後 ESC 應恢復既有清空行為")
        print("PASS：等待期間鎖定與失敗後恢復")
    }

    private static func testEditorKeyGate() throws {
        let editor = InputTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 32))
        let spy = InputSpy()
        editor.inputDelegate = spy
        editor.isEditable = false
        editor.keyDown(with: keyEvent(36, characters: "\r"))
        editor.keyDown(with: keyEvent(53, characters: "\u{1b}"))
        try expect(spy.enterCount == 0 && spy.escapeCount == 0, "鎖定時按鍵不得送出或觸發 ESC")

        editor.isEditable = true
        editor.keyDown(with: keyEvent(36, characters: "\r"))
        editor.keyDown(with: keyEvent(53, characters: "\u{1b}"))
        try expect(spy.enterCount == 1 && spy.escapeCount == 1, "解鎖後 Enter 與 ESC 應恢復接收")
        print("PASS：文字區按鍵守門")
    }
}
