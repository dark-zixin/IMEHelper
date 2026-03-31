//
//  SourceAppInfo.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa
import ApplicationServices

/// 來源 app 資訊
/// 記錄觸發快捷鍵時前景 app 的相關資訊
struct SourceAppInfo {

    /// 來源 app 的 process ID
    let pid: pid_t

    /// Bundle Identifier
    let bundleIdentifier: String?

    /// App 名稱
    let appName: String

    /// 視窗標題
    let windowTitle: String

    /// 選中分頁的描述（透過 AXTabGroup 取得，比視窗標題更精確）
    let tabDescription: String

    /// 選中分頁的索引（用來區分同描述的不同分頁）
    let tabIndex: Int

    /// 用於綁定識別的 key
    var bindingKey: String {
        if !tabDescription.isEmpty {
            return "\(pid)_\(tabDescription)_\(tabIndex)"
        }
        return "\(pid)_\(windowTitle)"
    }

    /// 從當前前景 app 取得資訊
    static func fromFrontmostApp() -> SourceAppInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("SourceAppInfo: 無法取得前景 app")
            return nil
        }

        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "未知 App"
        let bundleId = frontApp.bundleIdentifier

        let windowInfo = getWindowInfo(pid: pid)

        return SourceAppInfo(
            pid: pid,
            bundleIdentifier: bundleId,
            appName: appName,
            windowTitle: windowInfo.windowTitle,
            tabDescription: windowInfo.tabDescription,
            tabIndex: windowInfo.tabIndex
        )
    }

    /// 從指定 PID 的 app 取得資訊（用於驗證視窗是否仍存在）
    static func fromApp(pid: pid_t) -> SourceAppInfo? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              !app.isTerminated else {
            return nil
        }

        let appName = app.localizedName ?? "未知 App"
        let bundleId = app.bundleIdentifier
        let windowInfo = getWindowInfo(pid: pid)

        return SourceAppInfo(
            pid: pid,
            bundleIdentifier: bundleId,
            appName: appName,
            windowTitle: windowInfo.windowTitle,
            tabDescription: windowInfo.tabDescription,
            tabIndex: windowInfo.tabIndex
        )
    }

    /// 透過 Accessibility API 取得焦點視窗標題、選中分頁描述和索引
    private static func getWindowInfo(pid: pid_t) -> (windowTitle: String, tabDescription: String, tabIndex: Int) {
        let appElement = AXUIElementCreateApplication(pid)

        // 取得焦點視窗
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let window = focusedWindow else {
            return ("", "", -1)
        }

        let axWindow = window as! AXUIElement

        // 取得視窗標題
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
        let windowTitle = titleValue as? String ?? ""

        // 嘗試取得選中分頁的描述和索引
        let (tabDesc, tabIdx) = getSelectedTabInfo(window: axWindow)

        return (windowTitle, tabDesc, tabIdx)
    }

    /// 從視窗的 AXTabGroup 中找到選中的分頁，回傳其 AXDescription 和索引
    private static func getSelectedTabInfo(window: AXUIElement) -> (description: String, index: Int) {
        // 取得視窗的子元素
        var children: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)

        guard let kids = children as? [AXUIElement] else {
            return ("", -1)
        }

        // 找到 AXTabGroup
        for child in kids {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)

            guard (role as? String) == "AXTabGroup" else {
                continue
            }

            // 列舉 tab group 的子元素（各分頁）
            var tabChildren: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &tabChildren)

            guard let tabs = tabChildren as? [AXUIElement] else {
                continue
            }

            var tabIndex = 0
            for tab in tabs {
                // 檢查是否為 AXRadioButton（分頁）
                var tabRole: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXRoleAttribute as CFString, &tabRole)
                guard (tabRole as? String) == "AXRadioButton" else {
                    continue
                }

                // 檢查是否為選中的分頁（AXValue = 1）
                var value: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXValueAttribute as CFString, &value)

                if let numValue = value as? NSNumber, numValue.intValue == 1 {
                    // 取得分頁描述
                    var desc: AnyObject?
                    AXUIElementCopyAttributeValue(tab, kAXDescriptionAttribute as CFString, &desc)
                    return (desc as? String ?? "", tabIndex)
                }

                tabIndex += 1
            }
        }

        return ("", -1)
    }
}
