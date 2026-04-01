//
//  InputPanel.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// InputPanel 事件委派協議
protocol InputPanelDelegate: AnyObject {
    /// 使用者按下 Enter 送出文字
    func inputPanelDidSubmit(_ panel: InputPanel, text: String)
    /// 窗口已關閉
    func inputPanelDidClose(_ panel: InputPanel)
}

/// 浮動輸入窗口
/// 提供一個半透明玻璃效果的浮動面板，讓使用者輸入文字
class InputPanel: NSPanel {

    /// 文字輸入區域
    private var textView: InputTextView!

    /// 捲動容器
    private var scrollView: NSScrollView!

    /// 玻璃效果背景
    private var visualEffectView: NSVisualEffectView!

    /// 底部提示標籤
    private var hintLabel: NSTextField!

    /// ESC 狀態機
    private var escStateMachine = EscStateMachine()

    /// 提示標籤自動隱藏的計時器
    private var hintTimer: Timer?

    /// 是否為程式主動關閉（跳過 windowShouldClose 確認對話框）
    /// 是否為程式主動關閉（跳過 windowShouldClose 確認對話框和 delegate 通知）
    var isClosingProgrammatically = false

    /// 是否為程式主動移動（不記錄到 rememberLast）
    private var isProgrammaticMove = false

    /// 來源 app 資訊
    private(set) var sourceAppInfo: SourceAppInfo?

    /// 是否為孤立狀態（目標視窗已關閉，不受 hideAll 影響）
    var isOrphaned = false

    /// 隱藏開始的時間（用於淘汰分數計算）
    var hiddenSince: Date?

    /// 是否被使用者手動隱藏（快捷鍵 toggle off）
    var isManuallyHidden: Bool = false

    /// 事件委派
    weak var panelDelegate: InputPanelDelegate?

    /// 初始化浮動輸入窗口
    /// 窗口最大自動展開高度
    private let maxAutoHeight: CGFloat = 400

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 80),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // 設定窗口屬性
        self.level = .floating
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false  // 需要接收鍵盤輸入
        self.isMovableByWindowBackground = true
        self.titlebarAppearsTransparent = false  // 保留標題列
        self.title = "IMEHelper 輸入面板"

        // 設定最小尺寸
        self.minSize = NSSize(width: 300, height: 60)

        // 設定自己為 NSWindowDelegate 以攔截關閉事件
        self.delegate = self

        setupVisualEffect()
        setupTextView()
        setupHintLabel()

        // 監聽窗口移動，記錄位置
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveNotification(_:)),
            name: NSWindow.didMoveNotification,
            object: self
        )

        // 監聽透明度變更
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowAlphaDidChange(_:)),
            name: SettingsManager.windowAlphaDidChangeNotification,
            object: nil
        )

        // 監聽字型大小變更
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontSizeDidChange(_:)),
            name: SettingsManager.fontSizeDidChangeNotification,
            object: nil
        )

        // 監聽文字變動，自動調整窗口高度
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChangeNotification(_:)),
            name: NSText.didChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// 覆寫 close() 確保清理 NotificationCenter observer
    override func close() {
        NotificationCenter.default.removeObserver(self)
        hintTimer?.invalidate()
        hintTimer = nil
        super.close()
    }

    // MARK: - UI 建構

    /// 設定玻璃效果背景
    private func setupVisualEffect() {
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.alphaValue = SettingsManager.shared.windowAlpha
        self.isOpaque = false
        self.backgroundColor = .clear
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        self.contentView = visualEffectView
    }

    /// 設定文字輸入區域
    private func setupTextView() {
        // 建立 NSScrollView 容器
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false  // 透明背景，讓玻璃效果顯現
        scrollView.borderType = .noBorder

        // 建立自訂 InputTextView
        textView = InputTextView()
        textView.inputDelegate = self
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false  // 純文字模式
        textView.drawsBackground = false  // 透明背景
        textView.font = NSFont.systemFont(ofSize: SettingsManager.shared.fontSize)
        textView.textColor = NSColor.labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true

        // 設定 NSTextView 的自動換行
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,  // 會被 widthTracksTextView 覆蓋
            height: CGFloat.greatestFiniteMagnitude
        )

        // 設定內邊距
        textView.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.documentView = textView

        // 加入玻璃效果背景上
        visualEffectView.addSubview(scrollView)

        // 設定 Auto Layout 約束（底部保留空間給提示標籤）
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
        ])
    }

    /// 設定底部提示標籤
    private func setupHintLabel() {
        hintLabel = NSTextField(labelWithString: "")
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = NSFont.systemFont(ofSize: 11)
        hintLabel.textColor = NSColor.secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.isHidden = true

        visualEffectView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            // scrollView 底部接到 hintLabel 上方
            scrollView.bottomAnchor.constraint(equalTo: hintLabel.topAnchor, constant: -2),

            // hintLabel 固定在底部
            hintLabel.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 8),
            hintLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -8),
            hintLabel.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -4),
            hintLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    // MARK: - 公開方法

    /// 標記為孤立狀態（目標視窗已關閉），更新標題列提示
    func markAsOrphaned() {
        isOrphaned = true
        self.title = "⚠ 目標視窗已關閉 — 請手動複製文字後關閉"
    }

    /// 標記為淘汰候選，更新標題列提示讓使用者決定
    func markAsEvictionCandidate() {
        isOrphaned = true  // 不受 hideAll 影響
        sourceAppInfo = nil  // 清掉來源，關閉時不切焦點
        self.title = "⚠ 窗口數量已達上限 — 請複製文字後關閉以釋放空間"
    }

    /// 設定來源 app 資訊（更新標題列顯示）
    func setSourceApp(_ info: SourceAppInfo) {
        sourceAppInfo = info

        if info.windowTitle.isEmpty {
            self.title = "輸入到：\(info.appName)"
        } else {
            self.title = "輸入到：\(info.appName) - \(info.windowTitle)"
        }
    }

    /// 取得輸入的文字
    var text: String {
        get {
            return textView.string
        }
        set {
            textView.string = newValue
        }
    }

    /// 顯示在指定位置
    /// - Parameters:
    ///   - caretPosition: 游標在螢幕上的座標（左上角原點系統），若為 nil 則顯示在螢幕中央
    ///   - caretHeight: 游標高度，用來計算窗口偏移量
    func showAt(caretPosition: NSPoint?, caretHeight: CGFloat) {
        let settings = SettingsManager.shared

        isProgrammaticMove = true
        switch settings.windowPositionMode {
        case .followCaret:
            // 跟著文字游標（原有邏輯）
            positionAtCaret(caretPosition: caretPosition, caretHeight: caretHeight)

        case .screenCenter:
            // 螢幕中央
            centerOnScreen()

        case .rememberLast:
            // 記住上次位置，並做螢幕邊界校正
            if let lastPosition = settings.lastWindowPosition {
                var pos = lastPosition
                let panelSize = self.frame.size

                // 找到包含此位置的螢幕，或退回主螢幕
                let targetScreen = NSScreen.screens.first(where: {
                    $0.visibleFrame.contains(NSPoint(x: pos.x + 1, y: pos.y + 1))
                }) ?? NSScreen.main

                if let screen = targetScreen {
                    let visibleFrame = screen.visibleFrame
                    // 確保窗口不超出螢幕可見範圍
                    pos.x = min(max(pos.x, visibleFrame.minX), visibleFrame.maxX - panelSize.width)
                    pos.y = min(max(pos.y, visibleFrame.minY), visibleFrame.maxY - panelSize.height)
                }

                self.setFrameOrigin(pos)
            } else {
                positionAtCaret(caretPosition: caretPosition, caretHeight: caretHeight)
            }
        }
        isProgrammaticMove = false

        // 顯示窗口並取得焦點
        hiddenSince = nil
        NSLog("InputPanel: 準備顯示窗口，位置 x=\(self.frame.origin.x), y=\(self.frame.origin.y)")
        self.makeKeyAndOrderFront(nil)

        // 確保 textView 取得焦點
        self.makeFirstResponder(textView)
        NSLog("InputPanel: 窗口已顯示")
    }

    /// 讓 textView 取得焦點（供外部呼叫）
    func focusTextView() {
        self.makeFirstResponder(textView)
    }

    /// 關閉窗口並清理資源
    func hidePanel() {
        hintTimer?.invalidate()
        hintTimer = nil
        escStateMachine.reset()
        hideHintLabel()

        // 通知 delegate 再 close，避免 close 觸發 windowShouldClose 的確認對話框
        let delegate = panelDelegate
        isClosingProgrammatically = true
        self.close()
        delegate?.inputPanelDidClose(self)
    }

    /// 重置 ESC 狀態機（文字變動時呼叫）
    func resetEscState() {
        escStateMachine.reset()
        hideHintLabel()
    }

    // MARK: - 私有方法

    /// 根據游標位置定位窗口
    private func positionAtCaret(caretPosition: NSPoint?, caretHeight: CGFloat) {
        let panelSize = self.frame.size

        guard let caret = caretPosition else {
            centerOnScreen()
            return
        }

        // Accessibility API 使用左上角原點座標系統
        // 需要轉換為 AppKit 的左下角原點座標系統
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(
            NSPoint(x: caret.x, y: NSMaxY($0.frame) - caret.y),
            $0.frame,
            false
        )}) ?? NSScreen.main else {
            centerOnScreen()
            return
        }

        let screenFrame = screen.visibleFrame
        let screenMaxY = NSMaxY(screen.frame)

        // 將左上角原點的 y 轉換為左下角原點
        let convertedCaretY = screenMaxY - caret.y

        // 預設放在游標上方（窗口底部對齊游標上方，留 4 點間距）
        let panelX = caret.x
        var panelY = convertedCaretY + 4

        // 上邊界檢查：如果窗口會超出螢幕頂部，改放到游標下方
        if panelY + panelSize.height > NSMaxY(screenFrame) {
            panelY = convertedCaretY - caretHeight - panelSize.height - 4
        }

        var finalX = panelX
        var finalY = panelY

        // 右邊界檢查
        if finalX + panelSize.width > NSMaxX(screenFrame) {
            finalX = NSMaxX(screenFrame) - panelSize.width - 8
        }

        // 左邊界檢查
        if finalX < NSMinX(screenFrame) {
            finalX = NSMinX(screenFrame) + 8
        }

        // 下邊界檢查
        if finalY < NSMinY(screenFrame) {
            finalY = NSMinY(screenFrame) + 8
        }

        self.setFrameOrigin(NSPoint(x: finalX, y: finalY))
    }

    /// 將窗口置中於螢幕
    private func centerOnScreen() {
        self.center()
    }

    /// 窗口移動通知處理 — 記錄位置到 SettingsManager
    /// 只有使用者手動拖動時才記錄，程式主動定位不記錄
    @objc private func windowDidMoveNotification(_ notification: Notification) {
        guard !isProgrammaticMove else { return }
        guard SettingsManager.shared.windowPositionMode == .rememberLast else { return }
        SettingsManager.shared.lastWindowPosition = self.frame.origin
    }

    /// 透明度變更通知處理 — 即時更新窗口透明度
    @objc private func windowAlphaDidChange(_ notification: Notification) {
        visualEffectView.alphaValue = SettingsManager.shared.windowAlpha
    }

    /// 字型大小變更通知處理 — 即時更新文字大小
    @objc private func fontSizeDidChange(_ notification: Notification) {
        textView.font = NSFont.systemFont(ofSize: SettingsManager.shared.fontSize)
        adjustWindowHeight()
    }

    /// 文字變動通知處理 — 自動調整窗口高度並重置 ESC 狀態
    @objc private func textDidChangeNotification(_ notification: Notification) {
        // 確認是自己的 textView 發出的通知
        guard let notifObject = notification.object as? NSTextView,
              notifObject === textView else {
            return
        }
        adjustWindowHeight()
        escStateMachine.reset()
        hideHintLabel()
    }

    /// 根據文字內容自動調整窗口高度
    private func adjustWindowHeight() {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        // 計算文字所需高度
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height

        // 加上內邊距和標題列高度
        let padding = textView.textContainerInset.height * 2 + 16  // 上下內邊距
        let titleBarHeight: CGFloat = 28
        let hintHeight: CGFloat = 20
        let targetHeight = textHeight + padding + titleBarHeight + hintHeight

        // 限制在最小高度和最大高度之間
        let minHeight: CGFloat = 80
        let newHeight = min(max(targetHeight, minHeight), maxAutoHeight)

        // 只有高度變化時才調整
        let currentHeight = self.frame.height
        if abs(newHeight - currentHeight) > 2 {
            var frame = self.frame
            // 保持底部位置不變，往上長（AppKit 座標系 origin 是左下角，不需要調整 origin.y）
            frame.size.height = newHeight
            isProgrammaticMove = true
            self.setFrame(frame, display: true, animate: false)
            isProgrammaticMove = false
        }
    }

    /// 顯示底部提示標籤
    private func showHintLabel(message: String) {
        hintLabel.stringValue = message
        hintLabel.isHidden = false

        // 取消之前的計時器
        hintTimer?.invalidate()

        // 設定自動隱藏計時器（與 ESC 超時同步 3 秒）
        hintTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.hideHintLabel()
            self?.escStateMachine.reset()
        }
    }

    /// 隱藏底部提示標籤
    private func hideHintLabel() {
        hintLabel.isHidden = true
        hintLabel.stringValue = ""
        hintTimer?.invalidate()
        hintTimer = nil
    }

    // MARK: - NSPanel 覆寫

    /// 讓 panel 可以成為 key window，以接收鍵盤事件
    override var canBecomeKey: Bool {
        return true
    }

    /// 讓 panel 可以成為 main window
    override var canBecomeMain: Bool {
        return true
    }
}

// MARK: - InputTextViewDelegate

extension InputPanel: InputTextViewDelegate {

    func inputTextViewDidPressEnter(_ textView: InputTextView) {
        // 淘汰候選或孤立 panel 不能送出，只能複製和關閉
        if isOrphaned {
            return
        }

        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            // 空文字按 Enter 直接關閉窗口
            hidePanel()
            return
        }

        // 傳原始文字，不是 trim 過的
        NSLog("InputPanel: 使用者送出文字，長度 \(textView.string.count)")
        panelDelegate?.inputPanelDidSubmit(self, text: textView.string)
    }

    func inputTextViewDidPressEscape(_ textView: InputTextView) {
        let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let action = escStateMachine.handleEscape(hasText: hasText)

        switch action {
        case .showWarning(let message):
            showHintLabel(message: message)

        case .clearText:
            textView.string = ""
            showHintLabel(message: "文字已清空，再按一次 ESC 關閉視窗")

        case .closePanel:
            hidePanel()

        case .none:
            break
        }
    }
}

// MARK: - NSWindowDelegate

extension InputPanel: NSWindowDelegate {

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 程式主動關閉時，跳過確認對話框（delegate 已由呼叫端通知）
        if isClosingProgrammatically {
            return true
        }

        let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        guard hasText else {
            // 沒有文字，直接關閉
            panelDelegate?.inputPanelDidClose(self)
            return true
        }

        // 有文字時跳出確認對話框
        let alert = NSAlert()
        alert.messageText = "確定要關閉嗎？"
        alert.informativeText = "輸入區還有未送出的文字，關閉後將會遺失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "關閉")
        alert.addButton(withTitle: "取消")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            panelDelegate?.inputPanelDidClose(self)
            return true
        }

        return false
    }
}
