//
//  HotkeyRecorderView.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/4/2.
//

import Cocoa

/// 快捷鍵錄製控制項
/// 點擊進入錄製模式，按下組合鍵完成設定
class HotkeyRecorderView: NSView {

    /// 錄製事件的 delegate
    weak var delegate: HotkeyRecorderDelegate?

    /// 是否正在錄製
    private var isRecording = false

    /// 顯示文字的標籤
    private let label = NSTextField(labelWithString: "")

    // MARK: - 初始化

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        updateDisplay()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        updateDisplay()
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        if isRecording {
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        } else {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }

    // MARK: - 顯示

    /// 更新顯示文字（從目前設定讀取）
    func updateDisplay() {
        let settings = SettingsManager.shared
        let text = Self.displayString(keyCode: settings.hotkeyKeyCode, modifierFlags: settings.hotkeyModifierFlags)
        label.stringValue = text
    }

    // MARK: - 事件處理

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            startRecording()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let keyCode = Int64(event.keyCode)
        let flags = event.modifierFlags

        // 純 ESC → 取消錄製
        if keyCode == 53 && flags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock) == [] {
            stopRecording()
            return
        }

        // 提取修飾鍵（只保留 Cmd/Shift/Ctrl/Option）
        let modifierMask: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        let activeModifiers = flags.intersection(modifierMask)

        // 要求至少一個實質修飾鍵（Cmd/Option/Control），純 Shift 不算
        let hasSubstantialModifier = activeModifiers.contains(.command)
            || activeModifiers.contains(.option)
            || activeModifiers.contains(.control)
        guard hasSubstantialModifier else {
            showUnsupported()
            return
        }

        let cgFlags = Self.nsModifiersToCGEventFlags(activeModifiers)

        // 檢查系統保留黑名單
        let candidate = ReservedHotkey(keyCode: keyCode, modifierFlags: cgFlags)
        if reservedHotkeys.contains(candidate) {
            showUnsupported()
            return
        }

        // 跟目前設定一樣 → 直接結束錄製（不算錯誤）
        let settings = SettingsManager.shared
        if keyCode == settings.hotkeyKeyCode && cgFlags == settings.hotkeyModifierFlags {
            stopRecording()
            return
        }

        // 記錄快捷鍵
        finishRecording(keyCode: keyCode, modifierFlags: cgFlags)
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            stopRecording()
        }
        return super.resignFirstResponder()
    }

    override func flagsChanged(with event: NSEvent) {
        // 錄製中不做特殊處理，等 keyDown 一起記錄
    }

    // MARK: - 錄製流程

    /// 顯示「不支援此組合」提示，1.5 秒後恢復錄製狀態
    private func showUnsupported() {
        label.stringValue = "不支援此組合"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.label.stringValue = "請按下快捷鍵…"
        }
    }

    private func startRecording() {
        isRecording = true
        label.stringValue = "請按下快捷鍵…"
        updateAppearance()
        window?.makeFirstResponder(self)
        delegate?.hotkeyRecorderDidStartRecording(self)
    }

    /// 取消錄製（外部可呼叫）
    func cancelRecording() {
        guard isRecording else { return }
        stopRecording()
    }

    private func stopRecording() {
        isRecording = false
        updateDisplay()
        updateAppearance()
        delegate?.hotkeyRecorderDidCancelRecording(self)
    }

    private func finishRecording(keyCode: Int64, modifierFlags: UInt64) {
        isRecording = false
        updateAppearance()

        // 存入設定
        SettingsManager.shared.setHotkey(keyCode: keyCode, modifierFlags: modifierFlags)
        updateDisplay()

        delegate?.hotkeyRecorderDidFinishRecording(self, keyCode: keyCode, modifierFlags: modifierFlags)
    }

    /// 外部呼叫：重設為預設快捷鍵
    func resetToDefault() {
        SettingsManager.shared.resetHotkey()
        updateDisplay()
    }

    // MARK: - 修飾鍵轉換

    /// NSEvent.ModifierFlags → CGEventFlags（UInt64）
    private static func nsModifiersToCGEventFlags(_ flags: NSEvent.ModifierFlags) -> UInt64 {
        var result: UInt64 = 0
        if flags.contains(.command) { result |= CGEventFlags.maskCommand.rawValue }
        if flags.contains(.shift) { result |= CGEventFlags.maskShift.rawValue }
        if flags.contains(.control) { result |= CGEventFlags.maskControl.rawValue }
        if flags.contains(.option) { result |= CGEventFlags.maskAlternate.rawValue }
        return result
    }

    // MARK: - 顯示文字

    /// 將 keyCode + modifierFlags 轉為可讀文字（如「⌘⇧Space」）
    static func displayString(keyCode: Int64, modifierFlags: UInt64) -> String {
        var parts: [String] = []

        // 修飾鍵符號（按 macOS 標準順序：⌃⌥⇧⌘）
        let flags = CGEventFlags(rawValue: modifierFlags)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }

        // 按鍵名稱
        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    /// keyCode → 可讀字串
    private static func keyCodeToString(_ keyCode: Int64) -> String {
        switch keyCode {
        // 特殊鍵
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 76: return "Enter"
        case 117: return "⌦"

        // 方向鍵
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"

        // F 鍵
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"

        // 數字鍵（主鍵盤）
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"

        // 字母鍵
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"

        // 符號鍵
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 42: return "\\"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"

        default: return "Key \(keyCode)"
        }
    }
}

// MARK: - Delegate

protocol HotkeyRecorderDelegate: AnyObject {
    /// 開始錄製（應暫停 HotkeyManager）
    func hotkeyRecorderDidStartRecording(_ recorder: HotkeyRecorderView)

    /// 取消錄製（應恢復 HotkeyManager）
    func hotkeyRecorderDidCancelRecording(_ recorder: HotkeyRecorderView)

    /// 錄製完成（應更新 HotkeyManager 並在延遲後恢復）
    func hotkeyRecorderDidFinishRecording(_ recorder: HotkeyRecorderView, keyCode: Int64, modifierFlags: UInt64)
}
