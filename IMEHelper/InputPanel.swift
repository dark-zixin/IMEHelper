//
//  InputPanel.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 浮動輸入窗口
/// 提供一個半透明玻璃效果的浮動面板，讓使用者輸入文字
class InputPanel: NSPanel {

    /// 文字輸入區域
    private var textView: NSTextView!

    /// 捲動容器
    private var scrollView: NSScrollView!

    /// 玻璃效果背景
    private var visualEffectView: NSVisualEffectView!

    /// 來源 app 資訊
    private(set) var sourceAppInfo: SourceAppInfo?

    /// 初始化浮動輸入窗口
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
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
        self.minSize = NSSize(width: 300, height: 150)

        setupVisualEffect()
        setupTextView()
    }

    // MARK: - UI 建構

    /// 設定玻璃效果背景
    private func setupVisualEffect() {
        visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .behindWindow
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

        // 建立 NSTextView
        textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false  // 純文字模式
        textView.drawsBackground = false  // 透明背景
        textView.font = NSFont.systemFont(ofSize: 14)
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

        // 設定 Auto Layout 約束
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
        ])
    }

    // MARK: - 公開方法

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
        let panelSize = self.frame.size

        if let caret = caretPosition {
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

            let screenFrame = screen.frame
            let screenMaxY = NSMaxY(screenFrame)

            // 將左上角原點的 y 轉換為左下角原點
            // 游標下方偏移 4 點
            let convertedY = screenMaxY - caret.y - caretHeight - 4
            let panelX = caret.x
            let panelY = convertedY - panelSize.height

            // 確保窗口不超出螢幕邊界
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

            // 下邊界檢查：如果窗口會超出螢幕底部，改放到游標上方
            if finalY < NSMinY(screenFrame) {
                finalY = screenMaxY - caret.y + 4
            }

            self.setFrameOrigin(NSPoint(x: finalX, y: finalY))
        } else {
            // 沒有游標位置，顯示在螢幕中央
            centerOnScreen()
        }

        // 顯示窗口並取得焦點
        self.makeKeyAndOrderFront(nil)

        // 確保 textView 取得焦點
        self.makeFirstResponder(textView)
    }

    /// 隱藏窗口
    func hidePanel() {
        self.orderOut(nil)
    }

    // MARK: - 私有方法

    /// 將窗口置中於螢幕
    private func centerOnScreen() {
        self.center()
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
