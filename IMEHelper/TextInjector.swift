//
//  TextInjector.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 文字回填邏輯
/// 透過剪貼簿 + 模擬 Cmd+V 的方式，將文字貼入目標 app
class TextInjector {

    private let pasteboardHelper = PasteboardHelper()

    /// 將文字回填到目標 app
    /// - Parameters:
    ///   - text: 要回填的文字
    ///   - targetPID: 目標 app 的 PID
    ///   - completion: 完成後的 callback
    func inject(text: String, targetPID: pid_t, completion: @escaping () -> Void) {
        // 1. 備份剪貼簿
        pasteboardHelper.backup()

        // 2. 寫入文字到剪貼簿
        pasteboardHelper.write(text: text)

        // 3. Activate 目標 app
        guard let app = NSRunningApplication(processIdentifier: targetPID),
              !app.isTerminated else {
            NSLog("TextInjector: 目標 app (PID: \(targetPID)) 已關閉，還原剪貼簿")
            pasteboardHelper.restore()
            completion()
            return
        }

        app.activate(options: [])

        // 4. 延遲一小段時間確保目標 app 準備好接收按鍵事件
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            // 5. 模擬 Cmd+V 貼上
            self.simulatePaste()

            // 6. 再延遲一小段時間後還原剪貼簿
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.pasteboardHelper.restore()
                NSLog("TextInjector: 文字回填完成，剪貼簿已還原")
                completion()
            }
        }
    }

    /// 模擬 Cmd+V 按鍵
    private func simulatePaste() {
        // V 鍵的 keyCode = 9
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)

        NSLog("TextInjector: 已模擬 Cmd+V 按鍵")
    }
}
