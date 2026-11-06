import Cocoa

final class CangjieLookupTextView: NSTextView {
    var compositionDidChange: (() -> Void)?
    private var inputMutationDepth = 0
    // super 內也可能同步通知 delegate；最外層輸入方法完成前，文字尚未穩定。
    var isComposing: Bool { inputMutationDepth > 0 || hasMarkedText() }

    // 選單列工具沒有標準「編輯」選單，須把編輯快捷鍵交回文字元件。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleEditingShortcut(event) || super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard !handleEditingShortcut(event) else { return }
        super.keyDown(with: event)
    }

    private func handleEditingShortcut(_ event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if flags == [.command, .shift], event.keyCode == 6, isEditable {
            undoManager?.redo()
            compositionDidChange?()
            return true
        }
        guard flags == .command else { return false }
        switch event.keyCode {
        case 8: copy(nil)
        case 0: selectAll(nil)
        case 9 where isEditable: paste(nil)
        case 7 where isEditable: cut(nil)
        case 6 where isEditable:
            undoManager?.undo()
            // 直接呼叫 undo manager 不保證收到文字 delegate 通知。
            compositionDidChange?()
        default: return false
        }
        return true
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        inputMutationDepth += 1
        defer { finishInputMutation() }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func unmarkText() {
        inputMutationDepth += 1
        defer { finishInputMutation() }
        super.unmarkText()
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        inputMutationDepth += 1
        defer { finishInputMutation() }
        super.insertText(string, replacementRange: replacementRange)
    }

    private func finishInputMutation() {
        inputMutationDepth -= 1
        if inputMutationDepth == 0 { compositionDidChange?() }
    }
}
