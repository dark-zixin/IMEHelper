//
//  PanelManagerWindowController.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/4/2.
//

import Cocoa
import SwiftUI

/// 窗口管理視窗控制器
/// 使用 NSHostingController 嵌入 SwiftUI 列表
class PanelManagerWindowController: NSWindowController {

    /// 單例實例
    private static var shared: PanelManagerWindowController?

    /// 開啟或顯示管理視窗（單例）
    static func show() {
        // 延遲一個短時間，讓 NSStatusItem menu dismiss 完成，避免 activation 時序競爭
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let existing = shared {
                NSApp.activate(ignoringOtherApps: true)
                existing.window?.makeKeyAndOrderFront(nil)
                return
            }

            let controller = PanelManagerWindowController()
            shared = controller
            NSApp.activate(ignoringOtherApps: true)
            controller.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - 初始化

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("manager.title", comment: "")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 400, height: 250)

        self.init(window: window)

        // 用 SwiftUI view 作為視窗內容，填滿視窗不主導大小
        let panelManagerView = PanelManagerView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let hostingController = NSHostingController(rootView: panelManagerView)
        // 防止 NSHostingController 根據內容調整視窗大小
        hostingController.sizingOptions = []
        window.contentViewController = hostingController

        // 恢復上次儲存的視窗位置和大小（必須在 contentViewController 設定之後）
        if let frameString = UserDefaults.standard.string(forKey: "PanelManagerWindowFrame") {
            window.setFrame(NSRectFromString(frameString), display: false)
        } else {
            window.center()
        }

        window.delegate = self
    }
}

// MARK: - NSWindowDelegate

extension PanelManagerWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // 儲存視窗位置和大小
        if let frame = window?.frame {
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: "PanelManagerWindowFrame")
        }
        PanelManagerWindowController.shared = nil
    }
}

// MARK: - SwiftUI Views

/// Panel 項目資料模型
struct PanelItem: Identifiable {
    let id: String              // bindingKey
    let appName: String         // 目標 app 名稱（孤立時也保留）
    let windowTitle: String     // 視窗標題（使用者可辨識）
    let fullText: String        // 完整文字
    let isOrphaned: Bool
    let hiddenSince: Date?      // 隱藏時間（排序用）

    /// 文字預覽（前 50 字，換行替換為空格）
    var textPreview: String {
        let preview = String(fullText.prefix(50)).replacingOccurrences(of: "\n", with: " ")
        return fullText.count > 50 ? preview + "…" : preview
    }

    /// 顯示用的 app 名稱（孤立時加標示）
    var displayAppName: String {
        isOrphaned ? String(format: NSLocalizedString("manager.orphaned_suffix", comment: ""), appName) : appName
    }
}

/// 窗口管理主視圖
struct PanelManagerView: View {
    @State private var items: [PanelItem] = []

    /// 目前展開的項目 ID
    @State private var expandedId: String?

    /// 全域字型大小
    @State private var fontSize: CGFloat = SettingsManager.shared.fontSize

    /// 最近複製的項目 ID（用於顯示「已複製」提示）
    @State private var copiedId: String?

    /// 確認對話框狀態
    @State private var showCloseAllAlert = false
    @State private var showCloseOrphanedAlert = false

    /// 從 WindowManager 載入真實資料
    private func loadData() {
        guard let windowManager = (NSApp.delegate as? AppDelegate)?.windowManager else { return }

        let newItems = windowManager.allBindings
            .filter { !$0.panel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.panel.isInjecting }
            .map { binding -> PanelItem in
                let panel = binding.panel
                return PanelItem(
                    id: binding.bindingKey,
                    appName: panel.lastAppName.isEmpty ? NSLocalizedString("manager.unknown_app", comment: "") : panel.lastAppName,
                    windowTitle: panel.lastWindowTitle,
                    fullText: panel.text,
                    isOrphaned: panel.isOrphaned,
                    hiddenSince: panel.hiddenSince
                )
            }
            .sorted { a, b in
                switch (a.hiddenSince, b.hiddenSince) {
                case (nil, nil): return false
                case (nil, _): return true
                case (_, nil): return false
                case let (aDate?, bDate?): return aDate > bDate
                }
            }

        items = newItems

        if let id = expandedId, !items.contains(where: { $0.id == id }) {
            expandedId = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                Spacer()
                Text(NSLocalizedString("manager.empty_state", comment: ""))
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Spacer()
            } else {
                // 列表（ScrollView + LazyVStack，平滑展開動畫）
                GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            let contentWidth = geometry.size.width - 24 // 扣除左右 padding
                            VStack(alignment: .leading, spacing: 4) {
                                // 頂部：資訊 + 按鈕
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        // App 名稱 + 孤立標示
                                        Text(item.displayAppName)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(item.isOrphaned ? .orange : .primary)
                                            .lineLimit(1)

                                        // 視窗標題
                                        if !item.windowTitle.isEmpty {
                                            Text(item.windowTitle)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }

                                        // 文字預覽（始終佔位，展開時透明）
                                        Text(item.textPreview)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .opacity(expandedId == item.id ? 0 : 1)
                                    }

                                    Spacer()

                                    // 按鈕
                                    HStack(spacing: 4) {
                                        Button(NSLocalizedString("manager.close", comment: "")) {
                                            // 關閉真實 panel 並清除 binding（不觸發焦點回跳）
                                            if let appDelegate = NSApp.delegate as? AppDelegate,
                                               let binding = appDelegate.windowManager.allBindings.first(where: { $0.bindingKey == item.id }) {
                                                let panel = binding.panel
                                                panel.isClosingProgrammatically = true
                                                panel.close()
                                                appDelegate.windowManager.remove(panel: panel)
                                            }
                                            if expandedId == item.id {
                                                expandedId = nil
                                            }
                                            // 從 windowManager 重新讀取，確保 UI 與真實狀態一致
                                            loadData()
                                        }
                                        .font(.system(size: 11))

                                        Button(copiedId == item.id ? NSLocalizedString("manager.copied", comment: "") : NSLocalizedString("manager.copy", comment: "")) {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(item.fullText, forType: .string)
                                            copiedId = item.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                if copiedId == item.id {
                                                    copiedId = nil
                                                }
                                            }
                                        }
                                        .font(.system(size: 11))
                                    }
                                }

                                // NSTextView 展開區域（始終存在，高度控制展開/收合）
                                let expandedHeight = ExpandedNSTextView.textHeight(
                                    item.fullText, fontSize: fontSize, maxWidth: contentWidth, maxHeight: 200
                                )
                                ExpandedNSTextView(text: item.fullText, fontSize: fontSize)
                                    .frame(height: expandedId == item.id ? expandedHeight : 0)
                                    .clipped()
                                    .background(expandedId == item.id ? Color(nsColor: .controlBackgroundColor) : .clear)
                                    .cornerRadius(expandedId == item.id ? 4 : 0)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedId = expandedId == item.id ? nil : item.id
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Divider()
                        }
                    }
                }
                } // GeometryReader

                // 底部工具列
                HStack {
                    Button(NSLocalizedString("manager.close_all", comment: "")) {
                        showCloseAllAlert = true
                    }
                    .alert(NSLocalizedString("manager.close_all_confirm", comment: ""), isPresented: $showCloseAllAlert) {
                        Button(NSLocalizedString("manager.close_all_button", comment: ""), role: .destructive) {
                            if let appDelegate = NSApp.delegate as? AppDelegate {
                                for item in items {
                                    if let binding = appDelegate.windowManager.allBindings.first(where: { $0.bindingKey == item.id }) {
                                        let panel = binding.panel
                                        panel.isClosingProgrammatically = true
                                        panel.close()
                                        appDelegate.windowManager.remove(panel: panel)
                                    }
                                }
                            }
                            expandedId = nil
                            loadData()
                        }
                        Button(NSLocalizedString("manager.cancel", comment: ""), role: .cancel) {}
                    } message: {
                        Text(String(format: NSLocalizedString("manager.close_all_message", comment: ""), items.count))
                    }

                    Button(NSLocalizedString("manager.close_orphaned", comment: "")) {
                        showCloseOrphanedAlert = true
                    }
                    .disabled(!items.contains { $0.isOrphaned })
                    .alert(NSLocalizedString("manager.close_orphaned_confirm", comment: ""), isPresented: $showCloseOrphanedAlert) {
                        Button(NSLocalizedString("manager.close_orphaned_button", comment: ""), role: .destructive) {
                            if let appDelegate = NSApp.delegate as? AppDelegate {
                                for item in items where item.isOrphaned {
                                    if let binding = appDelegate.windowManager.allBindings.first(where: { $0.bindingKey == item.id }) {
                                        let panel = binding.panel
                                        panel.isClosingProgrammatically = true
                                        panel.close()
                                        appDelegate.windowManager.remove(panel: panel)
                                    }
                                }
                            }
                            expandedId = nil
                            loadData()
                        }
                        Button(NSLocalizedString("manager.cancel", comment: ""), role: .cancel) {}
                    } message: {
                        let count = items.filter { $0.isOrphaned }.count
                        Text(String(format: NSLocalizedString("manager.close_orphaned_message", comment: ""), count))
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress { keyPress in
            guard keyPress.modifiers == .command else { return .ignored }
            switch keyPress.characters {
            case "=", "+":
                let newSize = min(fontSize + 2, 36)
                fontSize = newSize
                SettingsManager.shared.fontSize = newSize
                return .handled
            case "-":
                let newSize = max(fontSize - 2, 12)
                fontSize = newSize
                SettingsManager.shared.fontSize = newSize
                return .handled
            default:
                return .ignored
            }
        }
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.title == NSLocalizedString("manager.title", comment: "") {
                loadData()
            }
        }
    }
}

// MARK: - Preview

#Preview("窗口管理") {
    PanelManagerView()
        .frame(width: 500, height: 400)
}

// MARK: - NSTextView 包裝

struct ExpandedNSTextView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat

    /// 計算文字實際需要的高度（含 padding），最大不超過 maxHeight
    static func textHeight(_ text: String, fontSize: CGFloat, maxWidth: CGFloat, maxHeight: CGFloat) -> CGFloat {
        // 超過 500 字一定超過 maxHeight，直接回傳避免大量文字計算阻塞
        guard text.count < 500 else { return maxHeight }

        let font = NSFont.systemFont(ofSize: fontSize)
        let textInset: CGFloat = 16 // textContainerInset 上下各 8
        let boundingRect = (text as NSString).boundingRect(
            with: NSSize(width: maxWidth - 16, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(ceil(boundingRect.height) + textInset, maxHeight)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let width = scrollView.contentSize.width
        if width > 0 {
            textView.frame.size.width = width
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.widthTracksTextView = true
        }
        if textView.string != text {
            textView.string = text
        }
        // 更新字型大小
        let currentFont = textView.font
        let expectedFont = NSFont.systemFont(ofSize: fontSize)
        if currentFont?.pointSize != expectedFont.pointSize {
            textView.font = expectedFont
        }

        // 內容超過可見高度時才顯示 scroller
        let contentHeight = textView.frame.height
        let visibleHeight = scrollView.contentSize.height
        scrollView.hasVerticalScroller = contentHeight > visibleHeight
    }
}
