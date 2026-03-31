//
//  AppDelegate.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa
import ServiceManagement
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
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        hotkeyManager?.stop()
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

        // 設定選項（目前不做事，Phase 6 實作）
        let settingsItem = NSMenuItem(title: "設定...", action: nil, keyEquivalent: "")
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // 開機時啟動（checkbox）
        let launchAtLoginItem = NSMenuItem(
            title: "開機時啟動",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        // 根據目前狀態設定勾選
        launchAtLoginItem.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLoginItem)

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

    // MARK: - 開機啟動管理

    /// 切換開機時啟動的狀態
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp

        do {
            if sender.state == .on {
                // 目前已啟用，取消註冊
                try service.unregister()
                sender.state = .off
            } else {
                // 目前未啟用，進行註冊
                try service.register()
                sender.state = .on
            }
        } catch {
            NSLog("切換開機啟動失敗: \(error.localizedDescription)")
        }
    }

    /// 檢查目前是否已設定開機啟動
    private func isLaunchAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }

    // MARK: - 全域快捷鍵

    /// 設定全域快捷鍵管理器
    private func setupHotkeyManager() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.onHotkeyPressed = { [weak self] in
            self?.handleHotkeyPressed()
        }
        hotkeyManager.start()
    }

    /// 處理快捷鍵觸發事件
    private func handleHotkeyPressed() {
        // 取得來源 app 資訊（在建立 panel 之前，因為 panel 顯示後前景 app 會變成自己）
        let sourceApp = SourceAppInfo.fromFrontmostApp()

        guard let sourceApp = sourceApp else {
            return
        }

        // 檢查是否已有對應的窗口
        if let existingPanel = windowManager.find(for: sourceApp) {
            if existingPanel.isVisible {
                // 窗口已顯示 → 隱藏（toggle）
                existingPanel.orderOut(nil)
                // 歸還焦點給來源 app
                if let app = NSRunningApplication(processIdentifier: sourceApp.pid) {
                    app.activate(options: [])
                }
            } else {
                // 窗口存在但隱藏中 → 重新顯示
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

        // 背景 app 需要先 activate 才能顯示視窗
        NSApp.activate(ignoringOtherApps: true)

        // 顯示在游標位置或螢幕中央
        panel.showAt(
            caretPosition: caretInfo?.position,
            caretHeight: caretInfo?.height ?? 16
        )
    }

    // MARK: - App 切換監聽

    /// 監聽 app 切換事件，隱藏所有可見的 InputPanel
    @objc private func activeAppDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        // 切換到自己（IMEHelper）不做處理
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return
        }

        // 隱藏所有可見的 InputPanel（只用 orderOut，不觸發完整的 hidePanel）
        for binding in windowManager.allBindings {
            if binding.panel.isVisible {
                binding.panel.orderOut(nil)
            }
        }

        // 清理已關閉的 app 的綁定
        windowManager.cleanupTerminatedApps()
    }

    // MARK: - InputPanelDelegate

    func inputPanelDidSubmit(_ panel: InputPanel, text: String) {
        NSLog("AppDelegate: 收到送出文字，長度 \(text.count)")

        guard let sourceInfo = panel.sourceAppInfo else {
            NSLog("AppDelegate: 沒有來源 app 資訊，無法回填")
            panel.hidePanel()
            return
        }

        // 只隱藏視窗，不觸發 hidePanel 的完整邏輯
        // 因為 TextInjector 會負責 activate 目標 app，避免與 hidePanel 的 activate 衝突
        panel.orderOut(nil)

        // 用 TextInjector 回填文字
        textInjector.inject(text: text, targetPID: sourceInfo.pid) {
            // 回填完成後清理窗口狀態
            panel.text = ""
            panel.resetEscState()
            // 移除綁定
            self.windowManager.remove(panel: panel)
            NSLog("AppDelegate: 文字回填完成，已移除窗口綁定")
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
