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
