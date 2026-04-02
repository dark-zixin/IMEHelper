//
//  HotkeyManager.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 全域快捷鍵管理器
/// 使用 CGEvent tap 監聽 Cmd + Shift + Space 組合鍵
class HotkeyManager {

    /// 快捷鍵被觸發時的 callback
    var onHotkeyPressed: (() -> Void)?

    /// 帶 Cmd/Ctrl 修飾鍵的按鍵事件 callback（可能是切換視窗/分頁的操作）
    var onSwitchKeyPressed: (() -> Void)?

    /// 事件 tap 的參考，用於啟停控制和外部檢查是否啟動成功
    private(set) var eventTap: CFMachPort?

    /// 背景 RunLoop 執行緒
    private var runLoopThread: Thread?

    /// 背景執行緒的 RunLoop 參考，用於停止時退出
    private var backgroundRunLoop: CFRunLoop?

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

    // 如果事件 tap 被系統停用（例如超時），重新啟用
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
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

    let flags = event.flags
    let hasCmd = flags.contains(.maskCommand)
    let hasShift = flags.contains(.maskShift)
    let hasCtrl = flags.contains(.maskControl)
    let hasAlt = flags.contains(.maskAlternate)
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // 檢查快捷鍵：Cmd + Shift + Space（不含 Ctrl、Option）
    if hasCmd && hasShift && !hasCtrl && !hasAlt && keyCode == 49 {
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onHotkeyPressed?()
            }
        }
        // 攔截此事件，不傳遞給其他 app
        return nil
    }

    // 帶 Cmd 或 Ctrl 的 keyDown（可能是切換視窗/分頁的操作）
    // 排除不會切換分頁的常用編輯按鍵：A(0) S(1) Z(6) X(7) C(8) V(9)
    // 過濾 key repeat（長按不重複觸發）
    let editingKeys: Set<Int64> = [0, 1, 6, 7, 8, 9]
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if (hasCmd || hasCtrl) && !isRepeat && !editingKeys.contains(keyCode) {
        if let userInfo = userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onSwitchKeyPressed?()
            }
        }
    }

    // 放行事件，不攔截
    return Unmanaged.passUnretained(event)
}
