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

    /// 從當前前景 app 取得資訊
    /// - Returns: 來源 app 資訊，若無法取得則回傳 nil
    static func fromFrontmostApp() -> SourceAppInfo? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("SourceAppInfo: 無法取得前景 app")
            return nil
        }

        let pid = frontApp.processIdentifier
        let appName = frontApp.localizedName ?? "未知 App"
        let bundleId = frontApp.bundleIdentifier

        // 透過 Accessibility API 取得視窗標題
        let windowTitle = getWindowTitle(pid: pid)

        return SourceAppInfo(
            pid: pid,
            bundleIdentifier: bundleId,
            appName: appName,
            windowTitle: windowTitle
        )
    }

    /// 透過 Accessibility API 取得指定 app 的焦點視窗標題
    /// - Parameter pid: app 的 process ID
    /// - Returns: 視窗標題，若無法取得則回傳空字串
    private static func getWindowTitle(pid: pid_t) -> String {
        let appElement = AXUIElementCreateApplication(pid)

        // 取得焦點視窗
        var focusedWindow: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let window = focusedWindow else {
            NSLog("SourceAppInfo: 無法取得焦點視窗 (error: \(result.rawValue))")
            return ""
        }

        // 取得視窗標題
        var titleValue: AnyObject?
        let titleResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        guard titleResult == .success, let title = titleValue as? String else {
            NSLog("SourceAppInfo: 無法取得視窗標題 (error: \(titleResult.rawValue))")
            return ""
        }

        return title
    }
}
