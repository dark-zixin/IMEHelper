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
    /// 匹配 bindingKey（跳過 orphaned panel）
    /// 精確匹配失敗且有 loginLine 時，用 pid + loginLine 匹配（忽略 windowID 差異）
    func find(for sourceApp: SourceAppInfo) -> InputPanel? {
        // 精確匹配
        if let exact = bindings.first(where: { $0.bindingKey == sourceApp.bindingKey && !$0.panel.isOrphaned }) {
            return exact.panel
        }

        // loginLine fallback：有 loginLine 時，用 pid + loginLine 匹配
        if !sourceApp.loginLine.isEmpty {
            let loginKey = "|login:\(sourceApp.loginLine)"
            if let match = bindings.first(where: {
                $0.pid == sourceApp.pid && $0.bindingKey.contains(loginKey) && !$0.panel.isOrphaned
            }) {
                return match.panel
            }
        }

        if !bindings.isEmpty {
            NSLog("KEY比對失敗: 搜尋=\(sourceApp.bindingKey)")
            for b in bindings {
                NSLog("  存在: key=\(b.bindingKey), orphaned=\(b.panel.isOrphaned), text=\(b.panel.text.count)字")
            }
        }
        return nil
    }

    /// 含 fallback 的查找（處理 tab bar 消失的情況）
    /// 只在快捷鍵觸發時使用
    func findWithFallback(for sourceApp: SourceAppInfo) -> InputPanel? {
        if let exact = find(for: sourceApp) {
            return exact
        }

        // Fallback：tabDescription 為空（tab bar 隱藏）時用 windowID 匹配唯一候選
        guard sourceApp.windowID != 0, sourceApp.tabDescription.isEmpty else { return nil }

        let candidates = bindings.filter {
            $0.pid == sourceApp.pid && $0.windowID == sourceApp.windowID && !$0.panel.isOrphaned
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

    /// 嘗試補回 windowID == 0 的 binding 的真正 windowID
    /// - Parameter sourceApp: 當前的來源 app 資訊（含最新的 windowID）
    /// - Returns: 是否成功遷移
    @discardableResult
    func migrateIfNeeded(for sourceApp: SourceAppInfo) -> Bool {
        guard sourceApp.windowID != 0 else { return false }

        // 找到同 PID、windowID == 0、且 bindingKey 包含相同 windowTitle 的 binding
        let titleKey = "win:\(sourceApp.windowTitle)"
        guard let idx = bindings.firstIndex(where: {
            $0.pid == sourceApp.pid && $0.windowID == 0 && $0.bindingKey.contains(titleKey)
        }) else { return false }

        // 更新 windowID 和 bindingKey
        bindings[idx].windowID = sourceApp.windowID
        bindings[idx].bindingKey = sourceApp.bindingKey

        NSLog("WindowManager: migrate windowID 0 → \(sourceApp.windowID), key=\(sourceApp.bindingKey)")
        return true
    }

    /// 如果超過上限，淘汰一個 panel
    /// 排名制：文字排名(x1.5) + 時間排名，前 3 取字數最少的淘汰
    /// - Returns: true 表示可以繼續建新 panel，false 表示已顯示淘汰候選，不建新 panel
    func evictIfNeeded() -> Bool {
        let maxCount = SettingsManager.shared.maxPanelCount

        // 用總 binding 數檢查（包含 orphaned），只要不關就不能再開
        guard bindings.count >= maxCount else { return true }

        // 如果已經有淘汰候選正在等使用者處理，不再淘汰新的
        let hasOrphaned = bindings.contains { $0.panel.isOrphaned }
        if hasOrphaned { return false }

        // 排名只對非 orphaned 的做
        let activeIndices = (0..<bindings.count).filter { !bindings[$0].panel.isOrphaned }

        let n = activeIndices.count
        let now = Date()

        // 文字排名：字少的排名低（1 = 最少）
        let sortedByText = (0..<n).sorted {
            bindings[activeIndices[$0]].panel.text.count < bindings[activeIndices[$1]].panel.text.count
        }
        var textRank = [Int](repeating: 0, count: n)
        for (rank, localIdx) in sortedByText.enumerated() {
            textRank[localIdx] = rank + 1
        }

        // 時間排名：隱藏最久的排名低（1 = 最久）
        let sortedByTime = (0..<n).sorted {
            let t0 = bindings[activeIndices[$0]].panel.hiddenSince ?? now
            let t1 = bindings[activeIndices[$1]].panel.hiddenSince ?? now
            return t0 < t1
        }
        var timeRank = [Int](repeating: 0, count: n)
        for (rank, localIdx) in sortedByTime.enumerated() {
            timeRank[localIdx] = rank + 1
        }

        // 加權總分（localIdx → score）
        let textWeight = 1.5
        var scores: [(score: Double, localIdx: Int)] = []
        for i in 0..<n {
            let score = Double(textRank[i]) * textWeight + Double(timeRank[i])
            scores.append((score, i))
        }

        // 排序取前 3
        scores.sort { $0.score < $1.score }
        let top3 = Array(scores.prefix(3))

        // 從前 3 中挑字數最少的，字數相同挑隱藏最久的
        let evictLocal = top3.min { a, b in
            let textA = bindings[activeIndices[a.localIdx]].panel.text.count
            let textB = bindings[activeIndices[b.localIdx]].panel.text.count
            if textA != textB { return textA < textB }
            let timeA = bindings[activeIndices[a.localIdx]].panel.hiddenSince ?? now
            let timeB = bindings[activeIndices[b.localIdx]].panel.hiddenSince ?? now
            return timeA < timeB
        }!.localIdx

        let realIdx = activeIndices[evictLocal]
        let panel = bindings[realIdx].panel
        let hasText = !panel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        NSLog("WindowManager: 淘汰 panel（文字\(panel.text.count)字, hasText=\(hasText)）")

        if hasText {
            // 有文字：保留 binding（維持 count），標記為候選讓使用者決定
            panel.markAsEvictionCandidate()
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return false
        } else {
            // 空文字：移除 binding 並 close，可以繼續建新 panel
            bindings.remove(at: realIdx)
            panel.isClosingProgrammatically = true
            panel.close()
            return true
        }
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
                if binding.panel.hiddenSince == nil {
                    binding.panel.hiddenSince = Date()
                }
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
