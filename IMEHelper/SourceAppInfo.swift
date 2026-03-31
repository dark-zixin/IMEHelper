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

    /// CGWindowID（視窗存活期間唯一且穩定）
    let windowID: CGWindowID

    /// 選中分頁的描述（透過 AXTabGroup 取得）
    let tabDescription: String

    /// 選中分頁的索引（用來區分同描述的不同分頁）
    let tabIndex: Int

    /// 用於綁定識別的 key（三層結構：PID + 視窗 + 分頁）
    var bindingKey: String {
        // 視窗層：優先用 CGWindowID，fallback 到 windowTitle
        let windowPart: String
        if windowID != 0 {
            windowPart = "win:\(windowID)"
        } else {
            windowPart = "win:\(windowTitle)"
        }

        // 分頁層：有分頁資訊就加上
        let tabPart: String
        if !tabDescription.isEmpty {
            tabPart = "|tab:\(tabDescription)|idx:\(tabIndex)"
        } else {
            tabPart = ""
        }

        return "\(pid)|\(windowPart)\(tabPart)"
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
            windowID: windowInfo.windowID,
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
            windowID: windowInfo.windowID,
            tabDescription: windowInfo.tabDescription,
            tabIndex: windowInfo.tabIndex
        )
    }

    // MARK: - 私有方法

    /// 視窗資訊結構
    private struct WindowInfo {
        let windowTitle: String
        let windowID: CGWindowID
        let tabDescription: String
        let tabIndex: Int
    }

    /// 透過 Accessibility API 和 CGWindowList 取得焦點視窗完整資訊
    private static func getWindowInfo(pid: pid_t) -> WindowInfo {
        let appElement = AXUIElementCreateApplication(pid)

        // 取得焦點視窗
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let window = focusedWindow else {
            return WindowInfo(windowTitle: "", windowID: 0, tabDescription: "", tabIndex: -1)
        }

        let axWindow = window as! AXUIElement

        // 取得視窗標題
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
        let windowTitle = titleValue as? String ?? ""

        // 取得視窗位置和大小（用來匹配 CGWindowID）
        var axPosition = CGPoint.zero
        var axSize = CGSize.zero

        var posValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &posValue)
        if let pos = posValue {
            AXValueGetValue(pos as! AXValue, .cgPoint, &axPosition)
        }

        var sizeValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue)
        if let sz = sizeValue {
            AXValueGetValue(sz as! AXValue, .cgSize, &axSize)
        }

        // 取得 CGWindowID
        let windowID = getCGWindowID(pid: pid, title: windowTitle, position: axPosition, size: axSize)

        // 取得選中分頁資訊
        let (tabDesc, tabIdx) = getSelectedTabInfo(window: axWindow)

        return WindowInfo(windowTitle: windowTitle, windowID: windowID, tabDescription: tabDesc, tabIndex: tabIdx)
    }

    /// 透過 CGWindowListCopyWindowInfo 比對取得 CGWindowID
    private static func getCGWindowID(pid: pid_t, title: String, position: CGPoint, size: CGSize) -> CGWindowID {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }

        for info in windowInfoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }

            let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let wTitle = info[kCGWindowName as String] as? String ?? ""
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0

            // 用標題 + 大小比對（位置在座標系統轉換後可能有差異，大小比較穩定）
            if wTitle == title && abs(w - size.width) < 2 && abs(h - size.height) < 2 {
                return wid
            }
        }

        // 如果標題匹配失敗（可能標題有變動），用位置 + 大小比對
        let screenHeight = NSScreen.main?.frame.height ?? 1440
        for info in windowInfoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0 else {
                continue
            }

            let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0

            // AXPosition 是左下角原點，CGWindowList 是左上角原點
            // AX y 轉 CG y：cgY = screenHeight - axY - height
            // 但 AXPosition 回傳的其實是左上角原點（跟 CGWindowList 一樣）
            if abs(x - position.x) < 2 && abs(y - position.y) < 2 &&
               abs(w - size.width) < 2 && abs(h - size.height) < 2 {
                return wid
            }
        }

        return 0
    }

    /// 從視窗的 AXTabGroup 中找到選中的分頁，回傳其 AXDescription 和索引
    private static func getSelectedTabInfo(window: AXUIElement) -> (description: String, index: Int) {
        var children: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)

        guard let kids = children as? [AXUIElement] else {
            return ("", -1)
        }

        for child in kids {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)

            guard (role as? String) == "AXTabGroup" else {
                continue
            }

            var tabChildren: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &tabChildren)

            guard let tabs = tabChildren as? [AXUIElement] else {
                continue
            }

            var tabIndex = 0
            for tab in tabs {
                var tabRole: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXRoleAttribute as CFString, &tabRole)
                guard (tabRole as? String) == "AXRadioButton" else {
                    continue
                }

                var value: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXValueAttribute as CFString, &value)

                if let numValue = value as? NSNumber, numValue.intValue == 1 {
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
