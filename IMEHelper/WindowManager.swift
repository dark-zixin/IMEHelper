//
//  WindowManager.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 多窗口管理器
/// 管理所有 InputPanel 與來源 app/視窗的綁定關係
class WindowManager {

    /// 所有的窗口綁定
    private var bindings: [WindowBinding] = []

    /// 根據來源 app 資訊查詢已存在的窗口
    /// - Parameter sourceApp: 來源 app 資訊
    /// - Returns: 對應的 InputPanel，若不存在則回傳 nil
    func find(for sourceApp: SourceAppInfo) -> InputPanel? {
        let key = "\(sourceApp.pid)_\(sourceApp.windowTitle)"
        return bindings.first(where: { $0.bindingKey == key })?.panel
    }

    /// 綁定新的 InputPanel 到來源 app
    /// - Parameters:
    ///   - panel: 要綁定的 InputPanel
    ///   - sourceApp: 來源 app 資訊
    func bind(panel: InputPanel, to sourceApp: SourceAppInfo) {
        let binding = WindowBinding(
            pid: sourceApp.pid,
            windowTitle: sourceApp.windowTitle,
            panel: panel
        )
        bindings.append(binding)
    }

    /// 移除指定的 InputPanel 綁定
    /// - Parameter panel: 要移除的 InputPanel
    func remove(panel: InputPanel) {
        bindings.removeAll(where: { $0.panel === panel })
    }

    /// 隱藏所有可見的窗口（只用 orderOut，不觸發完整的 hidePanel）
    func hideAll() {
        for binding in bindings {
            if binding.panel.isVisible {
                binding.panel.orderOut(nil)
            }
        }
    }

    /// 取得所有綁定
    var allBindings: [WindowBinding] { bindings }

    /// 移除 PID 已不存在的綁定（清理已關閉的 app）
    func cleanupTerminatedApps() {
        bindings.removeAll { binding in
            guard let app = NSRunningApplication(processIdentifier: binding.pid) else {
                // 無法取得 app 資訊，代表已終止
                binding.panel.orderOut(nil)
                return true
            }
            if app.isTerminated {
                binding.panel.orderOut(nil)
                return true
            }
            return false
        }
    }
}
