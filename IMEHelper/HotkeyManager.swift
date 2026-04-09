//
//  HotkeyManager.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 不可錄製 / 監聽排除的系統保留快捷鍵
struct ReservedHotkey: Hashable {
    let keyCode: Int64
    let modifierFlags: UInt64  // CGEventFlags.rawValue
}

/// 系統保留快捷鍵黑名單
let reservedHotkeys: Set<ReservedHotkey> = {
    let cmd = CGEventFlags.maskCommand.rawValue
    let shift = CGEventFlags.maskShift.rawValue
    let opt = CGEventFlags.maskAlternate.rawValue
    let ctrl = CGEventFlags.maskControl.rawValue

    return [
        // app 切換
        ReservedHotkey(keyCode: 48, modifierFlags: cmd),              // Cmd+Tab
        ReservedHotkey(keyCode: 48, modifierFlags: cmd | shift),      // Cmd+Shift+Tab
        // Spotlight / 輸入法
        ReservedHotkey(keyCode: 49, modifierFlags: cmd),              // Cmd+Space
        ReservedHotkey(keyCode: 49, modifierFlags: cmd | opt),        // Cmd+Option+Space
        ReservedHotkey(keyCode: 49, modifierFlags: ctrl),             // Ctrl+Space
        // 視窗 / app 操作
        ReservedHotkey(keyCode: 12, modifierFlags: cmd),              // Cmd+Q
        ReservedHotkey(keyCode: 13, modifierFlags: cmd),              // Cmd+W
        ReservedHotkey(keyCode: 4, modifierFlags: cmd),               // Cmd+H
        ReservedHotkey(keyCode: 46, modifierFlags: cmd),              // Cmd+M
        ReservedHotkey(keyCode: 53, modifierFlags: cmd | opt),        // Cmd+Option+Esc
        // 螢幕截圖
        ReservedHotkey(keyCode: 20, modifierFlags: cmd | shift),      // Cmd+Shift+3
        ReservedHotkey(keyCode: 21, modifierFlags: cmd | shift),      // Cmd+Shift+4
        ReservedHotkey(keyCode: 23, modifierFlags: cmd | shift),      // Cmd+Shift+5
        // Mission Control
        ReservedHotkey(keyCode: 126, modifierFlags: ctrl),            // Ctrl+↑
        ReservedHotkey(keyCode: 125, modifierFlags: ctrl),            // Ctrl+↓
    ]
}()

/// 監聽排除的編輯按鍵 keyCode（不管修飾鍵，這些 keyCode 都不會切分頁）
/// A(0) S(1) Z(6) X(7) C(8) V(9)
let editingKeyCodes: Set<Int64> = [0, 1, 6, 7, 8, 9]

/// 全域快捷鍵管理器
/// 使用 CGEvent tap 監聯自訂快捷鍵組合
class HotkeyManager {

    /// 快捷鍵被觸發時的 callback
    var onHotkeyPressed: (() -> Void)?

    /// 帶 Cmd/Ctrl 修飾鍵的按鍵事件 callback（可能是切換視窗/分頁的操作）
    var onSwitchKeyPressed: (() -> Void)?

    /// 目前設定的快捷鍵 keyCode（背景執行緒讀取）
    var hotkeyKeyCode: Int64

    /// 目前設定的快捷鍵修飾鍵 flags（背景執行緒讀取）
    var hotkeyModifierFlags: UInt64

    /// 事件 tap 的參考，用於啟停控制和外部檢查是否啟動成功
    private(set) var eventTap: CFMachPort?

    /// 背景 RunLoop 執行緒
    private var runLoopThread: Thread?

    /// 背景執行緒的 RunLoop 參考，用於停止時退出
    private var backgroundRunLoop: CFRunLoop?

    /// 手動暫停旗標，防止 callback 自動重新啟用 tap
    var isPaused = false

    init() {
        let settings = SettingsManager.shared
        hotkeyKeyCode = settings.hotkeyKeyCode
        hotkeyModifierFlags = settings.hotkeyModifierFlags
    }

    /// 暫停事件 tap（錄製快捷鍵時使用）
    func pause() {
        isPaused = true
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            NSLog("HotkeyManager: 已暫停監聽")
        }
    }

    /// 恢復事件 tap
    func resume() {
        isPaused = false
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            NSLog("HotkeyManager: 已恢復監聽")
        }
    }

    /// 開始監聽全域快捷鍵
    func start() {
        guard eventTap == nil else {
            NSLog("HotkeyManager: 已經在監聽中")
            return
        }

        // 監聽按鍵按下事件
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        // 將 self 轉為 Unmanaged pointer，傳給 C callback
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: selfPointer
        ) else {
            NSLog("HotkeyManager: 無法建立 CGEvent tap，請確認已授予輔助使用權限")
            return
        }

        eventTap = tap

        // 在背景執行緒跑 RunLoop 來接收事件
        let thread = Thread {
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            let runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
            self.backgroundRunLoop = runLoop

            // 啟用事件 tap
            CGEvent.tapEnable(tap: tap, enable: true)

            NSLog("HotkeyManager: 開始監聽快捷鍵")
            CFRunLoopRun()
            NSLog("HotkeyManager: 背景 RunLoop 已結束")
        }
        thread.name = "HotkeyManager-EventTap"
        thread.start()
        runLoopThread = thread
    }

    /// 停止監聽全域快捷鍵
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }

        if let runLoop = backgroundRunLoop {
            CFRunLoopStop(runLoop)
            backgroundRunLoop = nil
        }

        runLoopThread = nil
        NSLog("HotkeyManager: 已停止監聽")
    }

    deinit {
        stop()
    }
}

/// CGEvent tap 的 C callback 函式
/// 注意：這是全域函式，不能直接存取 instance，需要透過 userInfo 取得 self
private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // 如果事件 tap 被系統停用（例如超時），重新啟用（但手動暫停時不自動恢復）
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if !manager.isPaused, let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                NSLog("HotkeyManager: 事件 tap 被停用，已重新啟用")
            }
        }
        return Unmanaged.passUnretained(event)
    }

    // 只處理按鍵按下事件
    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    let flags = event.flags
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // 比對修飾鍵：檢查設定的修飾鍵是否精確匹配（不多不少）
    let modifierMask: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
    let activeModifiers = flags.intersection(modifierMask)
    let requiredModifiers = CGEventFlags(rawValue: manager.hotkeyModifierFlags).intersection(modifierMask)

    // 檢查自訂快捷鍵
    if keyCode == manager.hotkeyKeyCode && activeModifiers == requiredModifiers {
        DispatchQueue.main.async {
            manager.onHotkeyPressed?()
        }
        // 攔截此事件，不傳遞給其他 app
        return nil
    }

    // 帶 Cmd 或 Ctrl 的 keyDown（可能是切換視窗/分頁的操作）
    // 排除：編輯按鍵（keyCode 層級）、系統保留快捷鍵（精確 keyCode+modifier 組合）
    // 過濾 key repeat（長按不重複觸發）
    let hasCmd = flags.contains(.maskCommand)
    let hasCtrl = flags.contains(.maskControl)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let currentCombo = ReservedHotkey(keyCode: keyCode, modifierFlags: activeModifiers.rawValue)
    if (hasCmd || hasCtrl) && !isRepeat
        && !editingKeyCodes.contains(keyCode)
        && !reservedHotkeys.contains(currentCombo) {
        DispatchQueue.main.async {
            manager.onSwitchKeyPressed?()
        }
    }

    // 放行事件，不攔截
    return Unmanaged.passUnretained(event)
}
