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

    /// 根據來源 app 資訊查詢已存在的窗口（精確匹配 bindingKey）
    /// 精確匹配 bindingKey
    func find(for sourceApp: SourceAppInfo) -> InputPanel? {
        return bindings.first(where: { $0.bindingKey == sourceApp.bindingKey })?.panel
    }

    /// 含 fallback 的查找
    /// 只在快捷鍵觸發時使用
    func findWithFallback(for sourceApp: SourceAppInfo) -> InputPanel? {
        if let exact = find(for: sourceApp) {
            return exact
        }

        guard sourceApp.windowID != 0 else { return nil }

        // Fallback 1：同 windowID + 同 tabDescription（處理 loginLine 消失/改變的情況）
        if !sourceApp.tabDescription.isEmpty {
            let candidates = bindings.filter {
                $0.pid == sourceApp.pid &&
                $0.windowID == sourceApp.windowID &&
                $0.bindingKey.contains("|tab:\(sourceApp.tabDescription)")
            }
            if candidates.count == 1 {
                return candidates[0].panel
            }
        }

        // Fallback 2：同 windowID 唯一候選（處理 tab bar 消失的情況）
        if sourceApp.tabDescription.isEmpty {
            let candidates = bindings.filter {
                $0.pid == sourceApp.pid && $0.windowID == sourceApp.windowID
            }
            if candidates.count == 1 {
                return candidates[0].panel
            }
        }

        return nil
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

    /// 隱藏所有可見的窗口
    /// 空 panel 直接移除 binding 並 close（沒有保留價值），有文字的 orderOut
    func hideAll() {
        var toClose: [InputPanel] = []
        for binding in bindings {
            guard binding.panel.isVisible, !binding.panel.isOrphaned else { continue }

            let hasText = !binding.panel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasText {
                binding.panel.orderOut(nil)
            } else {
                toClose.append(binding.panel)
            }
        }
        // 空 panel：移除 binding 並直接 close，不走 hidePanel 避免觸發 delegate 焦點回跳
        for panel in toClose {
            remove(panel: panel)
            panel.isClosingProgrammatically = true
            panel.close()
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
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
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
