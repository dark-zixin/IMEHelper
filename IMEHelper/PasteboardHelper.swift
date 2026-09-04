//
//  PasteboardHelper.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 剪貼簿備份項目，用於保存單一項目的所有資料格式
struct PasteboardBackupItem {
    let typeDataMap: [NSPasteboard.PasteboardType: Data]
}

/// 一次剪貼簿快照，不與後續交易共用可變狀態
struct PasteboardSnapshot {
    let items: [PasteboardBackupItem]
    let isComplete: Bool
}

/// 寫入剪貼簿後的核對結果
struct PasteboardWriteResult {
    let didSetString: Bool
    let readbackMatches: Bool
    let changeCount: Int
}

/// 剪貼簿操作封裝
final class PasteboardHelper {

    /// 建立目前剪貼簿的完整快照
    func makeSnapshot() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems else {
            return PasteboardSnapshot(items: [], isComplete: true)
        }

        var isComplete = true
        let backupItems = items.map { item -> PasteboardBackupItem in
            var typeDataMap: [NSPasteboard.PasteboardType: Data] = [:]
            if item.types.isEmpty {
                isComplete = false
            }
            for type in item.types {
                if let data = item.data(forType: type) {
                    typeDataMap[type] = data
                } else {
                    isComplete = false
                }
            }
            return PasteboardBackupItem(typeDataMap: typeDataMap)
        }

        return PasteboardSnapshot(items: backupItems, isComplete: isComplete)
    }

    /// 將文字寫入剪貼簿，並立即讀回核對
    func write(text: String) -> PasteboardWriteResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didSetString = pasteboard.setString(text, forType: .string)
        let readbackMatches = pasteboard.string(forType: .string) == text

        return PasteboardWriteResult(
            didSetString: didSetString,
            readbackMatches: readbackMatches,
            changeCount: pasteboard.changeCount
        )
    }

    /// 目前純文字是否仍是本次要送出的內容
    func contains(text: String) -> Bool {
        NSPasteboard.general.string(forType: .string) == text
    }

    /// 目前剪貼簿版本
    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    /// 還原指定快照
    @discardableResult
    func restore(_ snapshot: PasteboardSnapshot) -> Bool {
        var pasteboardItems: [NSPasteboardItem] = []
        for backupItem in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in backupItem.typeDataMap {
                guard item.setData(data, forType: type) else {
                    return false
                }
            }
            pasteboardItems.append(item)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !snapshot.items.isEmpty else {
            return true
        }

        return pasteboard.writeObjects(pasteboardItems)
    }
}
