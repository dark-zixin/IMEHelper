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

    // 浮動輸入窗口（Phase 5 才做多窗口，目前只用一個）
    private var inputPanel: InputPanel?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 建立 Menu Bar 圖示
        setupStatusItem()

        // 檢查 Accessibility 權限
        checkAccessibilityPermission()

        // 設定全域快捷鍵
        setupHotkeyManager()
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
        // 如果已有 InputPanel 且正在顯示，則隱藏（toggle 行為）
        if let panel = inputPanel, panel.isVisible {
            panel.hidePanel()
            return
        }

        // 取得來源 app 資訊（在建立 panel 之前，因為 panel 顯示後前景 app 會變成自己）
        let sourceApp = SourceAppInfo.fromFrontmostApp()

        // 取得游標位置
        let caretInfo = CaretPositionHelper.getCaretPosition()

        // 建立或重用 InputPanel
        if inputPanel == nil {
            let panel = InputPanel()
            panel.panelDelegate = self
            inputPanel = panel
        }

        guard let panel = inputPanel else {
            return
        }

        // 設定來源 app 資訊
        if let info = sourceApp {
            panel.setSourceApp(info)
        }

        // 清空之前的文字
        panel.text = ""

        // 背景 app 需要先 activate 才能顯示視窗
        NSApp.activate(ignoringOtherApps: true)

        // 顯示在游標位置或螢幕中央
        panel.showAt(
            caretPosition: caretInfo?.position,
            caretHeight: caretInfo?.height ?? 16
        )
    }

    // MARK: - Accessibility 權限檢查

    // MARK: - InputPanelDelegate

    func inputPanelDidSubmit(_ panel: InputPanel, text: String) {
        NSLog("AppDelegate: 收到送出文字，長度 \(text.count)")
        // Phase 4 才實作回填，目前只關閉窗口
        panel.hidePanel()
    }

    func inputPanelDidClose(_ panel: InputPanel) {
        NSLog("AppDelegate: 輸入窗口已關閉")
        // 清理窗口狀態（目前保留 inputPanel 實例以重用）
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
