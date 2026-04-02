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
                // hiddenSince 為 nil（剛建立/剛恢復）排最前，其他按 hiddenSince 從新到舊
                switch (a.hiddenSince, b.hiddenSince) {
                case (nil, nil): return false
                case (nil, _): return true
                case (_, nil): return false
                case let (aDate?, bDate?): return aDate > bDate
                }
            }

        items = newItems

        // 展開的項目如果不存在了，清除展開狀態
        if let id = expandedId, !items.contains(where: { $0.id == id }) {
            expandedId = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if items.isEmpty {
                // 空狀態
                Spacer()
                Text("目前沒有輸入窗口")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                Spacer()
            } else {
                // 列表
                ScrollViewReader { scrollProxy in
                List {
                    ForEach(items) { item in
                        PanelRowView(
                            item: item,
                            isExpanded: expandedId == item.id,
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedId = expandedId == item.id ? nil : item.id
                                }
                            },
                            onClose: {
                                withAnimation {
                                    items.removeAll { $0.id == item.id }
                                    if expandedId == item.id {
                                        expandedId = nil
                                    }
                                }
                            },
                            onCopy: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(item.fullText, forType: .string)
                            }
                        )
                    }
                }
                .listStyle(.plain)
                .onChange(of: items.count) { _, _ in
                    // 資料變化時捲到頂部
                    if let firstId = items.first?.id {
                        scrollProxy.scrollTo(firstId, anchor: .top)
                    }
                }
                } // ScrollViewReader

                // 底部工具列
                HStack {
                    Button("全部關閉") {
                        showCloseAllAlert = true
                    }
                    .alert("確定要關閉所有窗口嗎？", isPresented: $showCloseAllAlert) {
                        Button("關閉全部", role: .destructive) {
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
        .onAppear {
            loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            // 管理視窗變成前景時刷新資料
            if let window = notification.object as? NSWindow, window.title == "窗口管理" {
                loadData()
            }
        }
    }
}

/// 單列 Panel 視圖
struct PanelRowView: View {
    let item: PanelItem
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onClose: () -> Void
    let onCopy: () -> Void

    /// 複製按鈕的「已複製」提示狀態
    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 頂部：資訊 + 按鈕
            HStack(alignment: .top) {
                // 左邊：標籤區
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

                    // 文字預覽（收合時顯示）
                    if !isExpanded {
                        Text(item.textPreview)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 右邊：按鈕
                HStack(spacing: 4) {
                    Button("關閉") {
                        onClose()
                    }
                    .font(.system(size: 11))

                    Button(showCopied ? "已複製" : "複製") {
                        onCopy()
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showCopied = false
                        }
                    }
                    .font(.system(size: 11))
                }
            }

            // 展開時顯示完整文字（可捲動，最大 200px）
            if isExpanded {
                ScrollView {
                    Text(item.fullText)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 200)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onToggleExpand()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview("窗口管理") {
    PanelManagerView()
        .frame(width: 500, height: 400)
}
