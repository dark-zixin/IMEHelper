//
//  WindowBinding.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 窗口綁定，記錄一個 InputPanel 與其來源 app/視窗的對應關係
struct WindowBinding {
    /// 綁定識別 key（由 SourceAppInfo.bindingKey 產生）
    let bindingKey: String
    /// 來源 app 的 PID
    let pid: pid_t
    /// 來源視窗的 CGWindowID
    let windowID: CGWindowID
    /// 對應的 InputPanel
    let panel: InputPanel
}
