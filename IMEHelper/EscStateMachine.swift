//
//  EscStateMachine.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Foundation

/// ESC 三步狀態機
/// 狀態流程：idle → warned → cleared → closed
/// 空文字時：idle → warned → closed（跳過 cleared）
/// 超時 3 秒未按下一次 ESC 則重置回 idle
class EscStateMachine {

    /// 狀態機的狀態
    enum State {
        case idle     // 初始狀態
        case warned   // 已顯示警告提示
        case cleared  // 已清空文字
    }

    /// 狀態機回傳的動作
    enum Action {
        case showWarning(message: String)  // 顯示提示文字
        case clearText                      // 清空文字
        case closePanel                     // 關閉窗口
        case none                           // 不做事（超時重置後重新開始）
    }

    /// 目前狀態
    private(set) var state: State = .idle

    /// 上次狀態轉換的時間戳
    private var lastTransitionTime: Date?

    /// 超時時間（秒）
    private let timeout: TimeInterval = 3.0

    /// 處理 ESC 按鍵，回傳應執行的動作
    /// - Parameter hasText: 目前輸入區是否有文字
    /// - Returns: 應執行的動作
    func handleEscape(hasText: Bool) -> Action {
        // 檢查是否超時，超時則重置
        if let lastTime = lastTransitionTime,
           Date().timeIntervalSince(lastTime) > timeout {
            state = .idle
            lastTransitionTime = nil
        }

        switch state {
        case .idle:
            // 第一下 ESC：顯示提示
            state = .warned
            lastTransitionTime = Date()
            if hasText {
                return .showWarning(message: "再按一次 ESC 清空文字，再按一次關閉視窗")
            } else {
                return .showWarning(message: "再按一次 ESC 關閉視窗")
            }

        case .warned:
            lastTransitionTime = Date()
            if hasText {
                // 第二下 ESC：清空文字
                state = .cleared
                return .clearText
            } else {
                // 空文字時跳過 cleared，直接關閉
                state = .idle
                return .closePanel
            }

        case .cleared:
            // 第三下 ESC：關閉窗口
            state = .idle
            lastTransitionTime = nil
            return .closePanel
        }
    }

    /// 重置狀態（窗口關閉或文字變動時呼叫）
    func reset() {
        state = .idle
        lastTransitionTime = nil
    }
}
