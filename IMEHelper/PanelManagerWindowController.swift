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
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = PanelManagerWindowController()
        shared = controller
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 初始化

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "窗口管理"
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
        isOrphaned ? "\(appName) ⚠ 已失去目標" : appName
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
            .filter { !$0.panel.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { binding -> PanelItem in
                let panel = binding.panel
                return PanelItem(
                    id: binding.bindingKey,
                    appName: panel.lastAppName.isEmpty ? "未知" : panel.lastAppName,
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
                Text("目前沒有輸入窗口")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Spacer()
            } else {
                // 列表（ScrollView + LazyVStack，平滑展開動畫）
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
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
                                        Button("關閉") {
                                            // 關閉真實 panel 並清除 binding（不觸發焦點回跳）
                                            if let appDelegate = NSApp.delegate as? AppDelegate,
                                               let binding = appDelegate.windowManager.allBindings.first(where: { $0.bindingKey == item.id }) {
                                                let panel = binding.panel
                                                panel.isClosingProgrammatically = true
                                                panel.close()
                                                appDelegate.windowManager.remove(panel: panel)
                                            }
                                            withAnimation {
                                                items.removeAll { $0.id == item.id }
                                                if expandedId == item.id {
                                                    expandedId = nil
                                                }
                                            }
                                        }
                                        .font(.system(size: 11))

                                        Button(copiedId == item.id ? "已複製" : "複製") {
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
                                let expandedHeight = TestNSTextViewWrapper.textHeight(
                                    item.fullText, fontSize: fontSize, maxWidth: 460, maxHeight: 200
                                )
                                TestNSTextViewWrapper(text: item.fullText, fontSize: fontSize)
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

                // 底部工具列
                HStack {
                    Button("全部關閉") {
                        showCloseAllAlert = true
                    }
                    .alert("確定要關閉所有窗口嗎？", isPresented: $showCloseAllAlert) {
                        Button("關閉全部", role: .destructive) {
                            // 關閉所有真實 panel 並清除 binding（不觸發焦點回跳）
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
                            withAnimation {
                                items.removeAll()
                                expandedId = nil
                            }
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        Text("共 \(items.count) 個窗口的文字將會遺失。")
                    }

                    Button("關閉孤立") {
                        showCloseOrphanedAlert = true
                    }
                    .disabled(!items.contains { $0.isOrphaned })
                    .alert("確定要關閉所有孤立窗口嗎？", isPresented: $showCloseOrphanedAlert) {
                        Button("關閉孤立", role: .destructive) {
                            // 關閉所有孤立的真實 panel 並清除 binding（不觸發焦點回跳）
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
                            withAnimation {
                                items.removeAll { $0.isOrphaned }
                                if let id = expandedId, !items.contains(where: { $0.id == id }) {
                                    expandedId = nil
                                }
                            }
                        }
                        Button("取消", role: .cancel) {}
                    } message: {
                        let count = items.filter { $0.isOrphaned }.count
                        Text("共 \(count) 個孤立窗口的文字將會遺失。")
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
            if let window = notification.object as? NSWindow, window.title == "窗口管理" {
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

// MARK: - NSTextView 測試（暫時）

struct TestNSTextViewContentView: View {
    /// 模擬 panel 資料
    struct TestItem: Identifiable {
        let id: Int
        let appName: String
        let windowTitle: String
        var fullText: String
    }

    @State private var items: [TestItem] = [
        TestItem(id: 1, appName: "Terminal", windowTitle: "測試 1：單行 + 更高高度", fullText: "短文字測試"),
        TestItem(id: 2, appName: "iTerm2", windowTitle: "測試 2：兩行文字", fullText: "第一行文字\n第二行文字"),
        TestItem(id: 3, appName: "Terminal", windowTitle: "測試 3：貼上剪貼簿", fullText: "（點擊「貼上剪貼簿」替換此文字）"),
    ]
    @State private var expandedId: Int?
    @State private var fontSize: CGFloat = SettingsManager.shared.fontSize

    var body: some View {
        VStack(spacing: 0) {
            // 控制區
            HStack {
                Button("貼上剪貼簿到第 3 項") {
                    guard let text = NSPasteboard.general.string(forType: .string) else { return }
                    if let index = items.firstIndex(where: { $0.id == 3 }) {
                        items[index].fullText = text
                    }
                }
                Text("剪貼簿：\(NSPasteboard.general.string(forType: .string)?.count ?? 0) 字")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("字型：\(Int(fontSize))pt")
                    .font(.system(size: 11))
                Button("-") {
                    let newSize = max(fontSize - 2, 12)
                    fontSize = newSize
                    SettingsManager.shared.fontSize = newSize
                }
                Button("+") {
                    let newSize = min(fontSize + 2, 36)
                    fontSize = newSize
                    SettingsManager.shared.fontSize = newSize
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 列表（用 ScrollView + ForEach 取代 List，避免行高動畫跳躍）
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            // 頂部：資訊 + 按鈕
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.appName)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)

                                    if !item.windowTitle.isEmpty {
                                        Text(item.windowTitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    // 文字預覽（始終佔位，展開時隱藏文字但保留高度）
                                    let preview = String(item.fullText.prefix(50)).replacingOccurrences(of: "\n", with: " ")
                                    Text(item.fullText.count > 50 ? preview + "…" : preview)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .opacity(expandedId == item.id ? 0 : 1)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Button("關閉") {}
                                        .font(.system(size: 11))
                                    Button("複製") {}
                                        .font(.system(size: 11))
                                }
                            }

                            // NSTextView 始終存在，用高度控制展開/收合
                            let expandedHeight = TestNSTextViewWrapper.textHeight(item.fullText, fontSize: fontSize, maxWidth: 460, maxHeight: 200)
                            TestNSTextViewWrapper(text: item.fullText, fontSize: fontSize)
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
    }
}

struct TestNSTextViewWrapper: NSViewRepresentable {
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
