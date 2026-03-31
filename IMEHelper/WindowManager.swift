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

    /// 含 fallback 的查找（處理分頁關閉後 tab bar 消失的情況）
    /// 只在快捷鍵觸發和 tryRestore 時使用
    func findWithFallback(for sourceApp: SourceAppInfo) -> InputPanel? {
        // 精確匹配
        if let exact = find(for: sourceApp) {
            return exact
        }

        // Fallback：只有當 tabDescription 為空時才啟用（代表 tab bar 已隱藏，只剩一個分頁）
        // 如果有 tabDescription 但精確匹配失敗，代表這個分頁確實沒有 panel
        guard sourceApp.windowID != 0, sourceApp.tabDescription.isEmpty else { return nil }

        let candidates = bindings.filter {
            $0.pid == sourceApp.pid && $0.windowID == sourceApp.windowID
        }

        guard candidates.count == 1 else { return nil }

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

    /// 檢查同一視窗內的綁定，其分頁是否還存在
    /// - Parameter currentTabDescriptions: 當前視窗中所有分頁的描述列表
    /// - Parameter windowID: 要檢查的視窗 CGWindowID
    @discardableResult
    func cleanupClosedTabs(windowID: CGWindowID, currentTabDescriptions: [String], windowTitle: String) -> [InputPanel] {
        guard windowID != 0 else { return [] }

        // 找出同 windowID 下帶 tab 描述的所有綁定
        let tabBindings = bindings.filter {
            $0.windowID == windowID && $0.bindingKey.contains("|tab:")
        }
        guard !tabBindings.isEmpty else { return [] }

        if !currentTabDescriptions.isEmpty {
            // 有 tab 列表：用描述計數比對
            var availableCounts: [String: Int] = [:]
            for desc in currentTabDescriptions where !desc.isEmpty {
                availableCounts[desc, default: 0] += 1
            }

            var cleanedPanels: [InputPanel] = []
            bindings.removeAll { binding in
                guard binding.windowID == windowID,
                      let tabRange = binding.bindingKey.range(of: "|tab:") else { return false }
                let tabDesc = String(binding.bindingKey[tabRange.upperBound...])
                guard !tabDesc.isEmpty else { return false }

                let count = availableCounts[tabDesc, default: 0]
                if count > 0 {
                    availableCounts[tabDesc] = count - 1
                    return false
                }

                cleanedPanels.append(binding.panel)
                return true
            }
            return cleanedPanels
        } else {
            // tab bar 隱藏（只剩一個分頁）：用視窗標題比對
            // 分頁描述通常包含視窗標題（例如描述 "dark@Mac: ~ (-zsh)" 包含標題 "dark@Mac: ~"）
            var cleanedPanels: [InputPanel] = []
            bindings.removeAll { binding in
                guard binding.windowID == windowID,
                      let tabRange = binding.bindingKey.range(of: "|tab:") else { return false }
                let tabDesc = String(binding.bindingKey[tabRange.upperBound...])
                guard !tabDesc.isEmpty else { return false }

                // 如果分頁描述包含視窗標題，視為存活的分頁
                if tabDesc.contains(windowTitle) && !windowTitle.isEmpty {
                    return false
                }

                // 不匹配的分頁已關閉
                cleanedPanels.append(binding.panel)
                return true
            }
            return cleanedPanels
        }
    }
}
