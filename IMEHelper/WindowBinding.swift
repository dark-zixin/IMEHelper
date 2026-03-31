//
//  WindowBinding.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 窗口綁定，記錄一個 InputPanel 與其來源 app/視窗的對應關係
struct WindowBinding {
    /// 來源 app 的 PID
    let pid: pid_t
    /// 來源視窗的標題（用來區分同一 app 的不同分頁）
    let windowTitle: String
    /// 對應的 InputPanel
    let panel: InputPanel

    /// 用來做唯一識別的 key
    var bindingKey: String {
        return "\(pid)_\(windowTitle)"
    }
}
