//
//  SettingsWindowController.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa
import ServiceManagement

/// 設定視窗控制器
/// 使用程式碼建立 UI，提供窗口位置、透明度、開機啟動等設定
class SettingsWindowController: NSWindowController {

    /// 單例實例，確保只有一個設定視窗
    private static var shared: SettingsWindowController?

    /// 窗口位置下拉選單
    private var positionPopUpButton: NSPopUpButton!

    /// 字型大小滑桿
    private var fontSizeSlider: NSSlider!

    /// 字型大小數值標籤
    private var fontSizeValueLabel: NSTextField!

    /// 透明度滑桿
    private var alphaSlider: NSSlider!

    /// 透明度數值標籤
    private var alphaValueLabel: NSTextField!

    /// 窗口上限滑桿
    private var maxPanelSlider: NSSlider!

    /// 窗口上限數值標籤
    private var maxPanelValueLabel: NSTextField!

    /// 開機啟動 checkbox
    private var launchAtLoginCheckbox: NSButton!

    /// 開啟或顯示設定視窗（單例）
    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = SettingsWindowController()
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 初始化

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 370),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "IMEHelper 設定"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        setupUI()
        loadCurrentSettings()

        // 設定 delegate 以偵測視窗關閉
        window.delegate = self
    }

    // MARK: - UI 建構

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        let labelWidth: CGFloat = 100
        let controlX: CGFloat = padding + labelWidth + 8

        // 窗口位置區域
        let positionLabel = createLabel(text: "窗口位置：", frame: NSRect(
            x: padding, y: 310, width: labelWidth, height: 22
        ))
        contentView.addSubview(positionLabel)

        positionPopUpButton = NSPopUpButton(frame: NSRect(
            x: controlX, y: 308, width: 190, height: 26
        ), pullsDown: false)
        positionPopUpButton.addItems(withTitles: [
            "跟著文字游標",
            "螢幕中央",
            "記住上次位置"
        ])
        positionPopUpButton.target = self
        positionPopUpButton.action = #selector(positionModeChanged(_:))
        contentView.addSubview(positionPopUpButton)

        // 分隔線
        let separator1 = createSeparator(y: 295, width: 310, padding: padding)
        contentView.addSubview(separator1)

        // 字型大小區域
        let fontSizeLabel = createLabel(text: "文字大小：", frame: NSRect(
            x: padding, y: 262, width: labelWidth, height: 22
        ))
        contentView.addSubview(fontSizeLabel)

        fontSizeSlider = NSSlider(frame: NSRect(
            x: controlX, y: 262, width: 150, height: 22
        ))
        fontSizeSlider.minValue = 12
        fontSizeSlider.maxValue = 36
        fontSizeSlider.isContinuous = true
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(fontSizeSliderChanged(_:))
        contentView.addSubview(fontSizeSlider)

        fontSizeValueLabel = NSTextField(labelWithString: "14")
        fontSizeValueLabel.frame = NSRect(
            x: controlX + 155, y: 262, width: 40, height: 22
        )
        fontSizeValueLabel.alignment = .right
        contentView.addSubview(fontSizeValueLabel)

        // 分隔線
        let separator2 = createSeparator(y: 248, width: 310, padding: padding)
        contentView.addSubview(separator2)

        // 透明度區域
        let alphaLabel = createLabel(text: "窗口透明度：", frame: NSRect(
            x: padding, y: 215, width: labelWidth, height: 22
        ))
        contentView.addSubview(alphaLabel)

        alphaSlider = NSSlider(frame: NSRect(
            x: controlX, y: 215, width: 150, height: 22
        ))
        alphaSlider.minValue = 0.5
        alphaSlider.maxValue = 1.0
        alphaSlider.isContinuous = true
        alphaSlider.target = self
        alphaSlider.action = #selector(alphaSliderChanged(_:))
        contentView.addSubview(alphaSlider)

        alphaValueLabel = NSTextField(labelWithString: "80%")
        alphaValueLabel.frame = NSRect(
            x: controlX + 155, y: 215, width: 40, height: 22
        )
        alphaValueLabel.alignment = .right
        contentView.addSubview(alphaValueLabel)

        // 分隔線
        let separator3 = createSeparator(y: 201, width: 310, padding: padding)
        contentView.addSubview(separator3)

        // 窗口上限區域
        let maxPanelLabel = createLabel(text: "窗口上限：", frame: NSRect(
            x: padding, y: 168, width: labelWidth, height: 22
        ))
        contentView.addSubview(maxPanelLabel)

        maxPanelSlider = NSSlider(frame: NSRect(
            x: controlX, y: 168, width: 150, height: 22
        ))
        maxPanelSlider.minValue = 5
        maxPanelSlider.maxValue = 50
        maxPanelSlider.numberOfTickMarks = 0
        maxPanelSlider.isContinuous = true
        maxPanelSlider.target = self
        maxPanelSlider.action = #selector(maxPanelSliderChanged(_:))
        contentView.addSubview(maxPanelSlider)

        maxPanelValueLabel = NSTextField(labelWithString: "20")
        maxPanelValueLabel.frame = NSRect(
            x: controlX + 155, y: 168, width: 40, height: 22
        )
        maxPanelValueLabel.alignment = .right
        contentView.addSubview(maxPanelValueLabel)

        // 分隔線
        let separator4 = createSeparator(y: 154, width: 310, padding: padding)
        contentView.addSubview(separator4)

        // 開機啟動
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "開機時自動啟動", target: self, action: #selector(launchAtLoginChanged(_:)))
        launchAtLoginCheckbox.frame = NSRect(
            x: padding, y: 121, width: 200, height: 22
        )
        contentView.addSubview(launchAtLoginCheckbox)

        // 底部說明
        let noteLabel = NSTextField(labelWithString: "設定變更會立即生效")
        noteLabel.frame = NSRect(
            x: padding, y: 20, width: 310, height: 16
        )
        noteLabel.font = NSFont.systemFont(ofSize: 11)
        noteLabel.textColor = NSColor.secondaryLabelColor
        contentView.addSubview(noteLabel)
    }

    /// 建立文字標籤
    private func createLabel(text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.alignment = .right
        return label
    }

    /// 建立分隔線
    private func createSeparator(y: CGFloat, width: CGFloat, padding: CGFloat) -> NSBox {
        let separator = NSBox(frame: NSRect(x: padding, y: y, width: width, height: 1))
        separator.boxType = .separator
        return separator
    }

    // MARK: - 載入設定

    private func loadCurrentSettings() {
        let settings = SettingsManager.shared

        // 窗口位置模式
        positionPopUpButton.selectItem(at: settings.windowPositionMode.rawValue)

        // 字型大小
        fontSizeSlider.doubleValue = Double(settings.fontSize)
        updateFontSizeLabel()

        // 透明度
        alphaSlider.doubleValue = Double(settings.windowAlpha)
        updateAlphaLabel()

        // 窗口上限
        maxPanelSlider.integerValue = settings.maxPanelCount
        updateMaxPanelLabel()

        // 開機啟動
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - 事件處理

    @objc private func positionModeChanged(_ sender: NSPopUpButton) {
        guard let mode = SettingsManager.WindowPositionMode(rawValue: sender.indexOfSelectedItem) else {
            return
        }
        SettingsManager.shared.windowPositionMode = mode
    }

    @objc private func fontSizeSliderChanged(_ sender: NSSlider) {
        SettingsManager.shared.fontSize = CGFloat(sender.doubleValue)
        updateFontSizeLabel()
    }

    @objc private func maxPanelSliderChanged(_ sender: NSSlider) {
        SettingsManager.shared.maxPanelCount = sender.integerValue
        updateMaxPanelLabel()
    }

    @objc private func alphaSliderChanged(_ sender: NSSlider) {
        SettingsManager.shared.windowAlpha = CGFloat(sender.doubleValue)
        updateAlphaLabel()
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        let service = SMAppService.mainApp

        do {
            if sender.state == .on {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("SettingsWindowController: 切換開機啟動失敗: \(error.localizedDescription)")
            // 回復 checkbox 狀態
            sender.state = service.status == .enabled ? .on : .off
        }
    }

    /// 更新字型大小數值標籤
    private func updateFontSizeLabel() {
        let size = Int(fontSizeSlider.doubleValue)
        fontSizeValueLabel.stringValue = "\(size)"
    }

    /// 更新透明度數值標籤
    private func updateAlphaLabel() {
        let percent = Int(alphaSlider.doubleValue * 100)
        alphaValueLabel.stringValue = "\(percent)%"
    }

    /// 更新窗口上限數值標籤
    private func updateMaxPanelLabel() {
        maxPanelValueLabel.stringValue = "\(maxPanelSlider.integerValue)"
    }
}

// MARK: - NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 清除單例引用，下次開啟時重新建立
        SettingsWindowController.shared = nil
    }
}
