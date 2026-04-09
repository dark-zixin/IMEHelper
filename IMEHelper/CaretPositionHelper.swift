//
//  CaretPositionHelper.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa
import ApplicationServices

/// 文字游標位置輔助工具
/// 透過 Accessibility API 取得前景 app 的文字游標座標
class CaretPositionHelper {

    /// 游標資訊
    struct CaretInfo {
        /// 游標在螢幕上的座標（左上角原點）
        let position: NSPoint
        /// 游標高度（用來計算浮動窗口的偏移量）
        let height: CGFloat
    }

    /// 取得當前前景 app 的文字游標位置
    /// - Returns: 游標資訊，若無法取得則回傳 nil
    static func getCaretPosition() -> CaretInfo? {
        // 取得前景 app 的 PID
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            NSLog("CaretPositionHelper: 無法取得前景 app")
            return nil
        }

        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // 取得焦點元素
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusResult == .success, let element = focusedElement else {
            NSLog("CaretPositionHelper: 無法取得焦點元素 (error: \(focusResult.rawValue))")
            return nil
        }

        let axElement = element as! AXUIElement

        // 取得選取範圍
        var selectedRangeValue: AnyObject?
        let rangeResult = AXUIElementCopyAttributeValue(
            axElement,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        )

        guard rangeResult == .success, let rangeValue = selectedRangeValue else {
            NSLog("CaretPositionHelper: 無法取得選取範圍 (error: \(rangeResult.rawValue))")
            return nil
        }

        // 透過 kAXBoundsForRangeParameterizedAttribute 取得游標的螢幕座標
        var boundsValue: AnyObject?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            axElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )

        guard boundsResult == .success, let bounds = boundsValue else {
            NSLog("CaretPositionHelper: 無法取得游標座標 (error: \(boundsResult.rawValue))")
            return nil
        }

        // 將 AXValue 轉為 CGRect
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            NSLog("CaretPositionHelper: 無法解析 AXValue 為 CGRect")
            return nil
        }

        // 檢查座標是否合理（避免無效值）
        if rect.origin.x == 0 && rect.size.height == 0 {
            NSLog("CaretPositionHelper: 座標無效 (x=0, h=0)，判定為無法取得")
            return nil
        }

        // 座標有效，回傳游標資訊
        // Accessibility API 回傳的是螢幕座標（左上角原點）
        return CaretInfo(
            position: NSPoint(x: rect.origin.x, y: rect.origin.y),
            height: rect.size.height
        )
    }

    /// 取得螢幕中央位置作為 fallback
    /// - Returns: 螢幕中央的座標點
    static func screenCenter() -> NSPoint {
        guard let screen = NSScreen.main else {
            return NSPoint(x: 400, y: 300)
        }
        let frame = screen.frame
        return NSPoint(
            x: frame.midX,
            y: frame.midY
        )
    }
}
