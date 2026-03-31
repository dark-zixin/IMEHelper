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
class AppDelegate: NSObject, NSApplicationDelegate {

    // Menu Bar 狀態列項目
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 建立 Menu Bar 圖示
        setupStatusItem()

        // 檢查 Accessibility 權限
        checkAccessibilityPermission()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
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
