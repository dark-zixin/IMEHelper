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

    /// 事件 tap 的參考，用於啟停控制
    /// fileprivate 是因為同檔案的全域 callback 函式需要存取
    fileprivate var eventTap: CFMachPort?

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
        return Unmanaged.passRetained(event)
    }

    // 只處理按鍵按下事件
    guard type == .keyDown else {
        return Unmanaged.passRetained(event)
    }

    // 檢查修飾鍵：Cmd + Shift（不含其他修飾鍵）
    let flags = event.flags
    let requiredFlags: CGEventFlags = [.maskCommand, .maskShift]
    let hasRequired = flags.contains(requiredFlags)
    let hasExtra = flags.contains(.maskControl) || flags.contains(.maskAlternate)

    guard hasRequired && !hasExtra else {
        return Unmanaged.passRetained(event)
    }

    // 檢查按鍵是否為 Space（keyCode = 49）
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    guard keyCode == 49 else {
        return Unmanaged.passRetained(event)
    }

    // 觸發快捷鍵 callback
    if let userInfo = userInfo {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        // 回到主執行緒執行 callback
        DispatchQueue.main.async {
            manager.onHotkeyPressed?()
        }
    }

    // 攔截此事件，不傳遞給其他 app
    return nil
}
