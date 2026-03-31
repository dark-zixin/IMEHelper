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

    /// 用於綁定識別的 key（PID + CGWindowID + 分頁描述）
    var bindingKey: String {
        let windowPart: String
        if windowID != 0 {
            windowPart = "win:\(windowID)"
        } else {
            windowPart = "win:\(windowTitle)"
        }

        let tabPart: String
        if !tabDescription.isEmpty {
            tabPart = "|tab:\(tabDescription)"
        } else {
            tabPart = ""
        }

        return "\(pid)|\(windowPart)\(tabPart)"
    }

    /// 從當前前景 app 取得資訊
    static func fromFrontmostApp() -> SourceAppInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
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
            tabDescription: windowInfo.tabDescription
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
            tabDescription: windowInfo.tabDescription
        )
    }

    // MARK: - 私有方法

    private struct WindowInfo {
        let windowTitle: String
        let windowID: CGWindowID
        let tabDescription: String
    }

    /// 透過 Accessibility API 和 CGWindowList 取得焦點視窗完整資訊
    private static func getWindowInfo(pid: pid_t) -> WindowInfo {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let window = focusedWindow else {
            return WindowInfo(windowTitle: "", windowID: 0, tabDescription: "")
        }

        let axWindow = window as! AXUIElement

        // 視窗標題
        var titleValue: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
        let windowTitle = titleValue as? String ?? ""

        // 視窗位置和大小（匹配 CGWindowID 用）
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

        let windowID = getCGWindowID(pid: pid, title: windowTitle, position: axPosition, size: axSize)
        let tabDesc = getSelectedTabDescription(window: axWindow)

        return WindowInfo(windowTitle: windowTitle, windowID: windowID, tabDescription: tabDesc)
    }

    /// 從視窗的 AXTabGroup 中取得選中分頁的 AXDescription
    private static func getSelectedTabDescription(window: AXUIElement) -> String {
        var children: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)

        guard let kids = children as? [AXUIElement] else { return "" }

        for child in kids {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == "AXTabGroup" else { continue }

            var tabChildren: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &tabChildren)
            guard let tabs = tabChildren as? [AXUIElement] else { continue }

            for tab in tabs {
                var tabRole: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXRoleAttribute as CFString, &tabRole)
                guard (tabRole as? String) == "AXRadioButton" else { continue }

                var value: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXValueAttribute as CFString, &value)

                if let numValue = value as? NSNumber, numValue.intValue == 1 {
                    var desc: AnyObject?
                    AXUIElementCopyAttributeValue(tab, kAXDescriptionAttribute as CFString, &desc)
                    return desc as? String ?? ""
                }
            }
        }

        return ""
    }

    /// 取得指定 app 焦點視窗中所有分頁的描述列表
    static func getAllTabDescriptions(pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success, let window = focusedWindow else { return [] }

        let axWindow = window as! AXUIElement
        var children: AnyObject?
        AXUIElementCopyAttributeValue(axWindow, kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement] else { return [] }

        for child in kids {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == "AXTabGroup" else { continue }

            var tabChildren: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &tabChildren)
            guard let tabs = tabChildren as? [AXUIElement] else { continue }

            var descriptions: [String] = []
            for tab in tabs {
                var tabRole: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXRoleAttribute as CFString, &tabRole)
                guard (tabRole as? String) == "AXRadioButton" else { continue }

                var desc: AnyObject?
                AXUIElementCopyAttributeValue(tab, kAXDescriptionAttribute as CFString, &desc)
                descriptions.append(desc as? String ?? "")
            }
            return descriptions
        }

        return []
    }

    /// 透過 CGWindowListCopyWindowInfo 比對取得 CGWindowID
    private static func getCGWindowID(pid: pid_t, title: String, position: CGPoint, size: CGSize) -> CGWindowID {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return 0
        }

        // 第一輪：標題 + 位置 + 大小
        for info in windowInfoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  info[kCGWindowIsOnscreen as String] as? Bool == true else {
                continue
            }

            let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let wTitle = info[kCGWindowName as String] as? String ?? ""
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0

            if wTitle == title &&
               abs(x - position.x) < 2 && abs(y - position.y) < 2 &&
               abs(w - size.width) < 2 && abs(h - size.height) < 2 {
                return wid
            }
        }

        // 第二輪：位置 + 大小
        for info in windowInfoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == pid,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  info[kCGWindowIsOnscreen as String] as? Bool == true else {
                continue
            }

            let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
            let x = bounds["X"] ?? 0
            let y = bounds["Y"] ?? 0
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0

            if abs(x - position.x) < 2 && abs(y - position.y) < 2 &&
               abs(w - size.width) < 2 && abs(h - size.height) < 2 {
                return wid
            }
        }

        return 0
    }
}
