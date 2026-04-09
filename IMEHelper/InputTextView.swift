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

    /// 防止 NSColorPanel 影響文字顏色
    override func changeColor(_ sender: Any?) {
        // 不做任何事，阻擋 NSColorPanel 的 changeColor 廣播
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // 精確匹配修飾鍵，避免 Cmd+Shift+Z 被當成 Cmd+Z
        let hasCommand = flags.contains(.command)
        let hasShift = flags.contains(.shift)
        let hasOption = flags.contains(.option)
        let hasControl = flags.contains(.control)

        // 純 Cmd 組合鍵（不含 Shift、Option、Control）
        if hasCommand && !hasShift && !hasOption && !hasControl {
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
            case 24:  // Cmd++ (Cmd+=) 放大文字
                let current = SettingsManager.shared.fontSize
                SettingsManager.shared.fontSize = min(current + 2, 36)
                return
            case 27:  // Cmd+- 縮小文字
                let current = SettingsManager.shared.fontSize
                SettingsManager.shared.fontSize = max(current - 2, 12)
                return
            default:
                break
            }
        }

        // Cmd+Shift 組合鍵
        if hasCommand && hasShift && !hasOption && !hasControl {
            switch keyCode {
            case 6:  // Cmd+Shift+Z 重做
                self.undoManager?.redo()
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
