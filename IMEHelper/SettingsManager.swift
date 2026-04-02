//
//  SettingsManager.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 設定管理器
/// 使用 UserDefaults 儲存和讀取使用者偏好設定
class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    /// 窗口位置模式
    enum WindowPositionMode: Int {
        case followCaret = 0    // 跟著文字游標（預設）
        case screenCenter = 1   // 螢幕中央
        case rememberLast = 2   // 記住上次位置
    }

    // MARK: - Keys

    private enum Keys {
        static let windowPositionMode = "windowPositionMode"
        static let lastWindowX = "lastWindowX"
        static let lastWindowY = "lastWindowY"
        static let windowAlpha = "windowAlpha"
        static let fontSize = "fontSize"
        static let maxPanelCount = "maxPanelCount"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifierFlags = "hotkeyModifierFlags"
    }

    // MARK: - 設定變更通知

    /// 窗口透明度變更通知
    static let windowAlphaDidChangeNotification = Notification.Name("SettingsManager.windowAlphaDidChange")

    /// 字型大小變更通知
    static let fontSizeDidChangeNotification = Notification.Name("SettingsManager.fontSizeDidChange")

    /// 快捷鍵變更通知
    static let hotkeyDidChangeNotification = Notification.Name("SettingsManager.hotkeyDidChange")

    /// 取得/設定窗口位置模式
    var windowPositionMode: WindowPositionMode {
        get {
            WindowPositionMode(rawValue: defaults.integer(forKey: Keys.windowPositionMode)) ?? .followCaret
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.windowPositionMode)
        }
    }

    /// 取得/設定上次窗口位置
    var lastWindowPosition: NSPoint? {
        get {
            guard defaults.object(forKey: Keys.lastWindowX) != nil else { return nil }
            return NSPoint(
                x: defaults.double(forKey: Keys.lastWindowX),
                y: defaults.double(forKey: Keys.lastWindowY)
            )
        }
        set {
            if let point = newValue {
                defaults.set(point.x, forKey: Keys.lastWindowX)
                defaults.set(point.y, forKey: Keys.lastWindowY)
            } else {
                defaults.removeObject(forKey: Keys.lastWindowX)
                defaults.removeObject(forKey: Keys.lastWindowY)
            }
        }
    }

    /// 取得/設定文字大小 (12-36)
    var fontSize: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.fontSize)
            return value > 0 ? CGFloat(value) : 14  // 預設 14
        }
        set {
            let clamped = min(max(Double(newValue), 12), 36)
            defaults.set(clamped, forKey: Keys.fontSize)
            NotificationCenter.default.post(name: Self.fontSizeDidChangeNotification, object: nil)
        }
    }

    /// 取得/設定窗口透明度 (0.5-1.0)
    var windowAlpha: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.windowAlpha)
            return value > 0 ? CGFloat(value) : 0.8  // 預設 0.8
        }
        set {
            let clamped = min(max(Double(newValue), 0.5), 1.0)
            defaults.set(clamped, forKey: Keys.windowAlpha)
            // 發送通知，讓已開啟的窗口即時更新
            NotificationCenter.default.post(name: Self.windowAlphaDidChangeNotification, object: nil)
        }
    }

    // MARK: - 快捷鍵設定

    /// 預設快捷鍵：Cmd + Shift + Space
    static let defaultHotkeyKeyCode: Int64 = 49
    static let defaultHotkeyModifierFlags: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue

    /// 取得/設定快捷鍵的 keyCode
    var hotkeyKeyCode: Int64 {
        get {
            let value = defaults.object(forKey: Keys.hotkeyKeyCode)
            return value != nil ? Int64(defaults.integer(forKey: Keys.hotkeyKeyCode)) : Self.defaultHotkeyKeyCode
        }
        set {
            defaults.set(Int(newValue), forKey: Keys.hotkeyKeyCode)
        }
    }

    /// 取得/設定快捷鍵的修飾鍵 flags（存為 UInt64）
    var hotkeyModifierFlags: UInt64 {
        get {
            let value = defaults.object(forKey: Keys.hotkeyModifierFlags)
            return value != nil ? UInt64(defaults.integer(forKey: Keys.hotkeyModifierFlags)) : Self.defaultHotkeyModifierFlags
        }
        set {
            defaults.set(Int(newValue), forKey: Keys.hotkeyModifierFlags)
        }
    }

    /// 設定快捷鍵並發送通知
    func setHotkey(keyCode: Int64, modifierFlags: UInt64) {
        hotkeyKeyCode = keyCode
        hotkeyModifierFlags = modifierFlags
        NotificationCenter.default.post(name: Self.hotkeyDidChangeNotification, object: nil)
    }

    /// 重設快捷鍵為預設值
    func resetHotkey() {
        setHotkey(keyCode: Self.defaultHotkeyKeyCode, modifierFlags: Self.defaultHotkeyModifierFlags)
    }

    // MARK: - 窗口上限

    /// 取得/設定窗口上限數量 (5-50)
    var maxPanelCount: Int {
        get {
            let value = defaults.integer(forKey: Keys.maxPanelCount)
            return value > 0 ? value : 20  // 預設 20
        }
        set {
            let clamped = min(max(newValue, 5), 50)
            defaults.set(clamped, forKey: Keys.maxPanelCount)
        }
    }
}
