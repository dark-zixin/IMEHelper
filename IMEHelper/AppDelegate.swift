//
//  AppDelegate.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa
import ApplicationServices

@main
class AppDelegate: NSObject, NSApplicationDelegate, InputPanelDelegate {

    // Menu Bar 狀態列項目
    private var statusItem: NSStatusItem!

    // 全域快捷鍵管理器
    private var hotkeyManager: HotkeyManager!

    // 多窗口管理器
    private var windowManager = WindowManager()

    // 文字回填注入器
    private var textInjector = TextInjector()

    // 視窗標題變化偵測計時器
    private var windowTitleCheckTimer: Timer?

    // 上次偵測到的前景視窗標題和 PID
    private var lastFrontmostKey: String = ""

    // 文字回填進行中旗標，抑制自動恢復
    private var isInjecting: Bool = false

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

        // 啟動視窗標題變化偵測（每 0.5 秒檢查一次，偵測同 app 內的視窗/分頁切換）
        startWindowTitleMonitor()
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

        // 設定選項
        let settingsItem = NSMenuItem(title: "設定...", action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 結束應用程式
        let quitItem = NSMenuItem(
            title: "結束 IMEHelper",
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

    // MARK: - 全域快捷鍵

    /// 設定全域快捷鍵管理器
    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.handleHotkeyPressed()
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
                if binding.panel.isVisible {
                    binding.panel.orderOut(nil)
                    binding.panel.isManuallyHidden = true
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

        // 檢查是否已有對應的窗口（含 fallback 匹配）
        if let existingPanel = windowManager.findWithFallback(for: sourceApp) {
            existingPanel.setSourceApp(sourceApp)

            if existingPanel.isVisible {
                // 窗口已顯示 → 隱藏（toggle）
                existingPanel.orderOut(nil)
                existingPanel.isManuallyHidden = true
                // 歸還焦點給來源 app
                if let app = NSRunningApplication(processIdentifier: sourceApp.pid) {
                    app.activate(options: [])
                }
            } else {
                // 窗口存在但隱藏中 → 重新顯示
                existingPanel.isManuallyHidden = false
                NSApp.activate(ignoringOtherApps: true)
                existingPanel.makeKeyAndOrderFront(nil)
                existingPanel.focusTextView()
            }
            return
        }

        // 沒有對應窗口 → 新建
        let caretInfo = CaretPositionHelper.getCaretPosition()
        let panel = InputPanel()
        panel.panelDelegate = self
        panel.setSourceApp(sourceApp)

        // 綁定到 WindowManager
        windowManager.bind(panel: panel, to: sourceApp)

        // 更新追蹤 key，防止 timer 把剛顯示的 panel 當成「標題變化」隱藏掉
        lastFrontmostKey = sourceApp.bindingKey

        // 背景 app 需要先 activate 才能顯示視窗
        NSApp.activate(ignoringOtherApps: true)

        // 顯示在游標位置或螢幕中央
        panel.showAt(
            caretPosition: caretInfo?.position,
            caretHeight: caretInfo?.height ?? 16
        )
    }

    // MARK: - App 切換監聽

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

        // 清理已關閉的 app 的綁定
        let cleanedPanels = windowManager.cleanupTerminatedApps()
        handleOrphanedPanels(cleanedPanels)

        // 延遲取得視窗標題，嘗試自動恢復
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.tryRestorePanel()
        }
    }

    // MARK: - 視窗標題變化偵測

    /// 啟動定時檢查前景視窗標題（偵測同 app 內的視窗/分頁切換）
    private func startWindowTitleMonitor() {
        windowTitleCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkWindowTitleChange()
        }
    }

    /// 檢查前景視窗標題是否變化，觸發隱藏/恢復；同時檢查視窗是否還存在
    private func checkWindowTitleChange() {
        // 正在回填中或自己是前景 app，不做處理
        guard !isInjecting,
              let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }

        // 檢查已關閉的視窗
        handleClosedWindows()

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
        let closedPanels = windowManager.cleanupClosedWindows()
        handleOrphanedPanels(closedPanels)
    }

    /// 統一處理孤立 panel（目標視窗/app 已關閉）
    private func handleOrphanedPanels(_ panels: [InputPanel]) {
        for panel in panels {
            let hasText = !panel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if hasText {
                // 標記為孤立，更新標題列提示，顯示 panel 讓使用者複製
                panel.markAsOrphaned()
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
                panel.focusTextView()
            } else {
                panel.hidePanel()
            }
        }
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

        // 更新追蹤 key
        lastFrontmostKey = sourceApp.bindingKey

        // 檢查是否有對應的窗口且有內容，且不是被手動隱藏的（含 fallback 匹配）
        if let existingPanel = windowManager.findWithFallback(for: sourceApp),
           !existingPanel.text.isEmpty,
           !existingPanel.isManuallyHidden {
            existingPanel.setSourceApp(sourceApp)
            NSApp.activate(ignoringOtherApps: true)
            existingPanel.makeKeyAndOrderFront(nil)
            existingPanel.focusTextView()
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
            // 目標已關閉，顯示警告，保留文字不關閉窗口
            let alert = NSAlert()
            alert.messageText = "目標視窗已關閉"
            alert.informativeText = "「\(sourceInfo.appName)」已關閉，無法回填文字。\n文字已保留在輸入窗口中，你可以手動複製。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "確定")
            alert.runModal()
            return
        }

        // 驗證目標視窗/分頁是否一致（防止來源視窗關閉但 app 仍在的情況）
        if let currentSourceApp = SourceAppInfo.fromApp(pid: sourceInfo.pid),
           currentSourceApp.bindingKey != sourceInfo.bindingKey {
            let currentDesc = currentSourceApp.tabDescription.isEmpty ? currentSourceApp.windowTitle : currentSourceApp.tabDescription
            let sourceDesc = sourceInfo.tabDescription.isEmpty ? sourceInfo.windowTitle : sourceInfo.tabDescription
            let alert = NSAlert()
            alert.messageText = "目標視窗可能已變更"
            alert.informativeText = "原始目標「\(sourceDesc)」已不是目前的前景視窗。\n目前為「\(currentDesc)」。\n\n是否仍要送出文字？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "送出")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            if response != .alertFirstButtonReturn {
                return
            }
        }

        // 設定回填旗標，抑制自動恢復
        isInjecting = true

        // 先移除綁定，避免回填過程中被自動恢復
        windowManager.remove(panel: panel)

        // 隱藏視窗（但保留文字，等回填成功後才清空）
        panel.orderOut(nil)
        panel.resetEscState()

        // 用 TextInjector 回填文字
        textInjector.inject(text: text, targetPID: sourceInfo.pid) { [weak self] success in
            guard let self = self else { return }
            self.isInjecting = false

            if success {
                // 回填成功，清空文字並關閉 panel
                panel.text = ""
                panel.hidePanel()
                NSLog("AppDelegate: 文字回填完成")
            } else {
                // 回填失敗，標記為孤立並重新顯示
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
        alert.messageText = "需要輔助使用權限"
        alert.informativeText = "IMEHelper 需要「輔助使用」權限才能偵測輸入法切換和游標位置。\n\n請前往「系統設定 → 隱私權與安全性 → 輔助使用」，將 IMEHelper 加入允許清單。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "開啟系統設定")
        alert.addButton(withTitle: "稍後再說")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // 開啟系統設定的輔助使用頁面
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
