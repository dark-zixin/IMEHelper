//
//  InputTextView.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 自訂 NSTextView 的事件委派協議
protocol InputTextViewDelegate: AnyObject {
    /// 使用者按下 Enter 鍵（送出文字）
    func inputTextViewDidPressEnter(_ textView: InputTextView)
    /// 使用者按下 ESC 鍵
    func inputTextViewDidPressEscape(_ textView: InputTextView)
}

/// 自訂 NSTextView，攔截 Enter 和 ESC 按鍵事件
class InputTextView: NSTextView {

    /// 輸入事件委派
    weak var inputDelegate: InputTextViewDelegate?

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd 組合鍵：讓標準編輯操作正常運作（複製、貼上、剪下、全選、復原）
        if flags.contains(.command) {
            switch keyCode {
            case 8:  // Cmd+C 複製
                self.copy(nil)
                return
            case 9:  // Cmd+V 貼上
                self.paste(nil)
                return
            case 7:  // Cmd+X 剪下
                self.cut(nil)
                return
            case 0:  // Cmd+A 全選
                self.selectAll(nil)
                return
            case 6:  // Cmd+Z 復原
                self.undoManager?.undo()
                return
            default:
                break
            }
        }

        // Enter 鍵 (keyCode = 36)
        if keyCode == 36 {
            if flags.contains(.shift) {
                // Shift + Enter → 插入換行
                self.insertNewline(nil)
            } else {
                // Enter → 通知委派送出
                inputDelegate?.inputTextViewDidPressEnter(self)
            }
            return
        }

        // ESC 鍵 (keyCode = 53)
        // 注意：輸入法聯想字窗口開著時，ESC 會被輸入法先攔截，不會傳到這裡
        if keyCode == 53 {
            inputDelegate?.inputTextViewDidPressEscape(self)
            return
        }

        super.keyDown(with: event)
    }
}
