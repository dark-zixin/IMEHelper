//
//  AppDelegate.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa
import ApplicationServices
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate, InputPanelDelegate {

    // Menu Bar 狀態列項目
    private var statusItem: NSStatusItem!

    // 全域快捷鍵管理器
    // 全域快捷鍵管理器（SettingsWindowController 的 delegate 需要存取）
    private(set) var hotkeyManager: HotkeyManager!

    // 多窗口管理器（PanelManagerWindowController 需要存取）
    private(set) var windowManager = WindowManager()

    // 文字回填注入器
    private var textInjector = TextInjector()

    // 慢速 timer（已關閉視窗清理 + 兜底偵測）
    private var windowTitleCheckTimer: Timer?

    // 上次偵測到的前景視窗標題和 PID
    private var lastFrontmostKey: String = ""

    // 文字回填進行中旗標，抑制自動恢復
    private var isInjecting: Bool = false

    // scheduleCheck 防重複執行旗標
    private var isChecking = false
    private var needsRecheck = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 建立 Menu Bar 圖示
        setupStatusItem()

        // 檢查 Accessibility 權限
        checkAccessibilityPermission()

        // 設定全域快捷鍵
        setupHotkeyManager()

        // 監聽 app 切換通知
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // 啟動慢速 timer（兜底偵測 + 已關閉視窗清理）
        startWindowTitleMonitor()

        // 監聽滑鼠點擊（偵測同 app 內的視窗/分頁切換）
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.scheduleCheck()
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        hotkeyManager?.stop()
        windowTitleCheckTimer?.invalidate()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Menu Bar 設定

    /// 建立 Menu Bar 狀態列項目和下拉選單
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "IMEHelper")
        }

        // 建立下拉選單
        let menu = NSMenu()

        // 版本資訊（不可點擊）
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "IMEHelper v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())

        // 設定選項
        let settingsItem = NSMenuItem(title: NSLocalizedString("menu.settings", comment: ""), action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // 窗口管理
        let panelManagerItem = NSMenuItem(title: NSLocalizedString("menu.panel_manager", comment: ""), action: #selector(openPanelManager(_:)), keyEquivalent: "")
        panelManagerItem.target = self
        menu.addItem(panelManagerItem)

        menu.addItem(NSMenuItem.separator())

        // 結束應用程式
        let quitItem = NSMenuItem(
            title: NSLocalizedString("menu.quit", comment: ""),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - 設定視窗

    /// 開啟設定視窗
    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.show()
    }

    /// 開啟窗口管理視窗
    @objc private func openPanelManager(_ sender: Any?) {
        PanelManagerWindowController.show()
    }

    // MARK: - 全域快捷鍵

    /// 設定全域快捷鍵管理器
    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.handleHotkeyPressed()
        }
        hotkeyManager.onSwitchKeyPressed = { [weak self] in
            self?.scheduleCheck()
        }
        hotkeyManager.start()

        // 如果啟動失敗（可能尚未授權），定時 retry
        if hotkeyManager.eventTap == nil {
            startHotkeyRetryTimer()
        }
    }

    /// 定時嘗試重新啟動快捷鍵監聽（等待使用者授權 Accessibility 權限後）
    private func startHotkeyRetryTimer() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            guard AXIsProcessTrusted() else { return }

            // 權限已授權，重新啟動
            self.hotkeyManager.start()
            if self.hotkeyManager.eventTap != nil {
                timer.invalidate()
                NSLog("AppDelegate: Accessibility 權限已授權，快捷鍵監聽已啟動")
            }
        }
    }

    /// 處理快捷鍵觸發事件
    private func handleHotkeyPressed() {
        // 取得來源 app 資訊（在建立 panel 之前，因為 panel 顯示後前景 app 會變成自己）
        let sourceApp = SourceAppInfo.fromFrontmostApp()

        guard let sourceApp = sourceApp else {
            return
        }

        // 如果前景 app 是 IMEHelper 自己，toggle 可見的 panel
        if sourceApp.pid == ProcessInfo.processInfo.processIdentifier {
            // 找到任何可見的 panel 並隱藏它
            var didHide = false
            for binding in windowManager.allBindings {
                if binding.panel.isVisible && !binding.panel.isOrphaned {
                    binding.panel.orderOut(nil)
                    binding.panel.isManuallyHidden = true
                    binding.panel.hiddenSince = Date()
                    didHide = true
                    // 歸還焦點給該 panel 的來源 app
                    if let info = binding.panel.sourceAppInfo,
                       let app = NSRunningApplication(processIdentifier: info.pid),
                       !app.isTerminated {
                        app.activate(options: [])
                    }
                }
            }
            if didHide {
                return
            }
            // 沒有可見的 panel，不做事
            return
        }

        // 先嘗試補回 windowID == 0 的 binding（讓後續 find 能匹配）
        windowManager.migrateIfNeeded(for: sourceApp)

        // 檢查是否已有對應的窗口（含 fallback 匹配）
        if let existingPanel = windowManager.findWithFallback(for: sourceApp) {
            existingPanel.setSourceApp(sourceApp)

            if existingPanel.isVisible {
                // 窗口已顯示 → 隱藏（toggle）
                existingPanel.orderOut(nil)
                existingPanel.isManuallyHidden = true
                existingPanel.hiddenSince = Date()
                // 歸還焦點給來源 app
                if let app = NSRunningApplication(processIdentifier: sourceApp.pid) {
                    app.activate(options: [])
                }
            } else {
                // 窗口存在但隱藏中 → 重新顯示
                existingPanel.isManuallyHidden = false
                existingPanel.hiddenSince = nil
                lastFrontmostKey = sourceApp.bindingKey
                NSApp.activate(ignoringOtherApps: true)
                existingPanel.makeKeyAndOrderFront(nil)
                existingPanel.focusTextView()
            }
            return
        }

        // 沒有對應窗口 → 新建（先檢查上限）
        guard windowManager.evictIfNeeded() else {
            // 已達上限且顯示了淘汰候選，不建新 panel
            return
        }
        let caretInfo = CaretPositionHelper.getCaretPosition()
        let panel = InputPanel()
        panel.panelDelegate = self
        panel.setSourceApp(sourceApp)



        // 綁定到 WindowManager
        NSLog("新建 panel: key=\(sourceApp.bindingKey)")
        windowManager.bind(panel: panel, to: sourceApp)

        // 更新追蹤 key，防止 timer 把剛顯示的 panel 當成「標題變化」隱藏掉
        lastFrontmostKey = sourceApp.bindingKey

        // 如果 windowID == 0，啟動 retry 嘗試補回
        if sourceApp.windowID == 0 {
            retryWindowID(pid: sourceApp.pid, panel: panel)
        }

        // 背景 app 需要先 activate 才能顯示視窗
        NSApp.activate(ignoringOtherApps: true)

        // 顯示在游標位置或螢幕中央
        panel.showAt(
            caretPosition: caretInfo?.position,
            caretHeight: caretInfo?.height ?? 16
        )
    }

    /// windowID == 0 時的 retry（50ms / 150ms / 300ms）
    private func retryWindowID(pid: pid_t, panel: InputPanel) {
        for delay in [0.05, 0.15, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak panel] in
                guard let self = self, let panel = panel else { return }

                // 重新取得來源 app 資訊
                guard let sourceApp = SourceAppInfo.fromApp(pid: pid),
                      sourceApp.windowID != 0 else { return }

                // 補回 binding 的 windowID，成功才更新 panel
                if self.windowManager.migrateIfNeeded(for: sourceApp) {
                    panel.setSourceApp(sourceApp)
                }
            }
        }
    }

    // MARK: - App 切換監聯

    /// 監聽 app 切換事件
    @objc private func activeAppDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // 切換到自己（IMEHelper）或正在回填中，不做處理
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier || isInjecting {
            return
        }

        // 隱藏所有可見的 InputPanel
        windowManager.hideAll()

        // 清理已關閉的 app（標記孤立或關閉空 panel）
        windowManager.cleanupTerminatedApps()

        // 延遲取得視窗標題，嘗試自動恢復
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.tryRestorePanel()
        }
    }

    // MARK: - 事件驅動分頁偵測

    /// 啟動慢速 timer（兜底偵測 + 已關閉視窗清理）
    /// 主要偵測由滑鼠/鍵盤監聽驅動，此 timer 負責：
    /// 1. 定期清理已關閉的視窗
    /// 2. 兜底偵測非 Cmd/Ctrl 的分頁切換（如觸控板手勢）
    private func startWindowTitleMonitor() {
        windowTitleCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.scheduleCheck()
        }
    }

    /// 事件驅動的分頁變化檢查（防重複執行）
    /// 滑鼠點擊、鍵盤操作、慢速 timer 都透過此方法觸發檢查
    private func scheduleCheck() {
        if isChecking {
            needsRecheck = true
            return
        }
        isChecking = true
        handleClosedWindows()
        checkWindowTitleChange()
        if needsRecheck {
            needsRecheck = false
            handleClosedWindows()
            checkWindowTitleChange()
        }
        isChecking = false
    }

    /// 檢查前景視窗標題是否變化，觸發隱藏/恢復
    private func checkWindowTitleChange() {
        // 正在回填中或自己是前景 app，不做處理
        guard !isInjecting,
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        // 取得當前前景視窗資訊
        guard let sourceApp = SourceAppInfo.fromFrontmostApp() else {
            return
        }

        let currentKey = sourceApp.bindingKey

        // 標題沒變，不做處理
        guard currentKey != lastFrontmostKey else {
            return
        }

        lastFrontmostKey = currentKey

        // 標題變了（同 app 內切換視窗/分頁）→ 隱藏所有窗口再嘗試恢復
        windowManager.hideAll()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.tryRestorePanel()
        }
    }

    /// 檢查並處理已關閉視窗的 panel
    private func handleClosedWindows() {
        windowManager.cleanupClosedWindows()
    }

    private func tryRestorePanel() {
        // 正在回填中，不恢復
        guard !isInjecting else { return }

        // 確認自己不是前景 app
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        guard let sourceApp = SourceAppInfo.fromFrontmostApp() else {
            return
        }

        // 順便嘗試補回 windowID
        windowManager.migrateIfNeeded(for: sourceApp)

        // 更新追蹤 key
        lastFrontmostKey = sourceApp.bindingKey

        // 檢查是否有對應的窗口且有內容，且不是被手動隱藏的（精確匹配）
        // tab bar 消失時自動恢復不生效，需使用者按快捷鍵觸發 fallback
        if let existingPanel = windowManager.find(for: sourceApp),
           !existingPanel.text.isEmpty,
           !existingPanel.isManuallyHidden {
            existingPanel.setSourceApp(sourceApp)
            existingPanel.hiddenSince = nil
            existingPanel.orderFrontRegardless()  // 只顯示不搶焦點，用戶點擊時才接收鍵盤
        }
    }

    // MARK: - InputPanelDelegate

    func inputPanelDidSubmit(_ panel: InputPanel, text: String) {
        NSLog("AppDelegate: 收到送出文字，長度 \(text.count)")

        guard let sourceInfo = panel.sourceAppInfo else {
            NSLog("AppDelegate: 沒有來源 app 資訊，無法回填")
            panel.hidePanel()
            return
        }

        // 檢查目標 app 是否還存在
        guard let targetApp = NSRunningApplication(processIdentifier: sourceInfo.pid),
              !targetApp.isTerminated else {
            // 目標已關閉，標記為孤立（保留 binding，讓管理視窗能看到）
            panel.markAsOrphaned()
            return
        }

        // 驗證目標視窗/分頁是否一致（防止來源視窗關閉但 app 仍在的情況）
        if let currentSourceApp = SourceAppInfo.fromApp(pid: sourceInfo.pid),
           currentSourceApp.bindingKey != sourceInfo.bindingKey {
            let currentDesc = currentSourceApp.tabDescription.isEmpty ? currentSourceApp.windowTitle : currentSourceApp.tabDescription
            let sourceDesc = sourceInfo.tabDescription.isEmpty ? sourceInfo.windowTitle : sourceInfo.tabDescription
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.target_changed_title", comment: "")
            alert.informativeText = String(format: NSLocalizedString("alert.target_changed_message", comment: ""), sourceDesc, currentDesc)
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("alert.target_changed_send", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("alert.target_changed_cancel", comment: ""))
            let response = alert.runModal()
            if response != .alertFirstButtonReturn {
                return
            }
        }

        // 設定回填旗標，抑制自動恢復
        isInjecting = true

        // 標記為回填中，避免被 hideAll/tryRestore 干擾
        panel.isInjecting = true

        // 隱藏視窗（但保留文字，等回填成功後才清空）
        panel.orderOut(nil)
        panel.resetEscState()

        // 用 TextInjector 回填文字
        textInjector.inject(text: text, targetPID: sourceInfo.pid) { [weak self] success in
            guard let self = self else { return }
            self.isInjecting = false

            if success {
                // 回填成功，清空文字、移除綁定、關閉 panel
                panel.text = ""
                panel.isInjecting = false
                self.windowManager.remove(panel: panel)
                panel.hidePanel()
                NSLog("AppDelegate: 文字回填完成")
            } else {
                // 回填失敗，標記為孤立並重新顯示（binding 保留，管理視窗可看到）
                panel.isInjecting = false
                panel.markAsOrphaned()
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                panel.focusTextView()
                NSLog("AppDelegate: 回填失敗，已重新顯示 panel")
            }

            if let current = SourceAppInfo.fromFrontmostApp() {
                self.lastFrontmostKey = current.bindingKey
            }
        }
    }

    func inputPanelDidClose(_ panel: InputPanel) {
        NSLog("AppDelegate: 輸入窗口已關閉")
        // 移除窗口綁定
        windowManager.remove(panel: panel)
        // 歸還焦點給來源 app
        if let info = panel.sourceAppInfo,
           let app = NSRunningApplication(processIdentifier: info.pid),
           !app.isTerminated {
            app.activate(options: [])
        }
    }

    // MARK: - Accessibility 權限檢查

    /// 檢查 Accessibility 權限，未授權時顯示提示
    private func checkAccessibilityPermission() {
        guard !AXIsProcessTrusted() else {
            return
        }

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("alert.accessibility_title", comment: "")
        alert.informativeText = NSLocalizedString("alert.accessibility_message", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("alert.accessibility_open_settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("alert.accessibility_later", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 開啟系統設定的輔助使用頁面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
