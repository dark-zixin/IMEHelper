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
    func find(for sourceApp: SourceAppInfo) -> InputPanel? {
        // 精確匹配 bindingKey
        if let exact = bindings.first(where: { $0.bindingKey == sourceApp.bindingKey }) {
            return exact.panel
        }

        // Fallback：同 windowID 內用 tabDescription 匹配（處理分頁關閉後索引位移）
        guard sourceApp.windowID != 0, !sourceApp.tabDescription.isEmpty else {
            return nil
        }

        let candidates = bindings.filter {
            $0.pid == sourceApp.pid &&
            $0.windowID == sourceApp.windowID &&
            $0.bindingKey.contains("tab:\(sourceApp.tabDescription)")
        }

        // 只有唯一匹配時才使用（避免同描述多分頁的誤配）
        guard candidates.count == 1 else {
            return nil
        }

        // 更新 bindingKey 以反映新的索引
        if let idx = bindings.firstIndex(where: { $0.panel === candidates[0].panel }) {
            bindings[idx] = WindowBinding(
                bindingKey: sourceApp.bindingKey,
                pid: bindings[idx].pid,
                windowID: bindings[idx].windowID,
                panel: bindings[idx].panel
            )
        }

        return candidates[0].panel
    }

    /// 綁定新的 InputPanel 到來源 app
    func bind(panel: InputPanel, to sourceApp: SourceAppInfo) {
        let binding = WindowBinding(
            bindingKey: sourceApp.bindingKey,
            pid: sourceApp.pid,
            windowID: sourceApp.windowID,
            panel: panel
        )
        bindings.append(binding)
    }

    /// 移除指定的 InputPanel 綁定
    func remove(panel: InputPanel) {
        bindings.removeAll(where: { $0.panel === panel })
    }

    /// 隱藏所有可見的窗口（只用 orderOut，不觸發完整的 hidePanel）
    func hideAll() {
        for binding in bindings {
            if binding.panel.isVisible && !binding.panel.isOrphaned {
                binding.panel.orderOut(nil)
            }
        }
    }

    /// 取得所有綁定
    var allBindings: [WindowBinding] { bindings }

    /// 移除 PID 已不存在的綁定（清理已關閉的 app）
    @discardableResult
    func cleanupTerminatedApps() -> [InputPanel] {
        var cleanedPanels: [InputPanel] = []
        bindings.removeAll { binding in
            guard let app = NSRunningApplication(processIdentifier: binding.pid) else {
                cleanedPanels.append(binding.panel)
                return true
            }
            if app.isTerminated {
                cleanedPanels.append(binding.panel)
                return true
            }
            return false
        }
        return cleanedPanels
    }

    /// 檢查所有綁定的視窗是否還存在（透過 CGWindowID 驗證）
    @discardableResult
    func cleanupClosedWindows() -> [InputPanel] {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var activeWindowIDs = Set<CGWindowID>()
        for info in windowInfoList {
            if let wid = info[kCGWindowNumber as String] as? CGWindowID {
                activeWindowIDs.insert(wid)
            }
        }

        var cleanedPanels: [InputPanel] = []
        bindings.removeAll { binding in
            guard binding.windowID != 0 else { return false }

            if !activeWindowIDs.contains(binding.windowID) {
                cleanedPanels.append(binding.panel)
                return true
            }
            return false
        }
        return cleanedPanels
    }
}
