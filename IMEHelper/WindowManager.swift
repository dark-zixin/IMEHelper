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
    /// 精確匹配失敗時，在同視窗內找唯一的候選（處理 tab bar 消失但 tty 提取不到的情況）
    func findWithFallback(for sourceApp: SourceAppInfo) -> InputPanel? {
        if let exact = find(for: sourceApp) {
            return exact
        }

        // 有 tty 但精確匹配失敗 → 確實沒有 panel（tty 不受 tab bar 影響）
        guard sourceApp.tty.isEmpty else { return nil }

        // 沒有 tty 也沒有 tabDescription → 嘗試用 windowID 匹配唯一候選
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
    /// 用當前 tty 和分頁列表交叉比對
    @discardableResult
    func cleanupClosedTabs(windowID: CGWindowID, currentTTY: String, currentTabDescriptions: [String]) -> [InputPanel] {
        guard windowID != 0 else { return [] }

        // 收集當前視窗內所有存活的識別資訊
        var aliveTTYs = Set<String>()
        if !currentTTY.isEmpty {
            aliveTTYs.insert(currentTTY)
        }

        // 注意：我們只能取得目前焦點分頁的 tty，無法取得其他分頁的 tty
        // 所以只檢查帶 tty 的綁定是否跟當前 tty 匹配

        var cleanedPanels: [InputPanel] = []
        // 不主動清理 — tty 比對只在單分頁時才可靠判斷
        // 多分頁時無法得知非焦點分頁的 tty，不能貿然清理
        return cleanedPanels
    }
}
