//
//  PasteboardHelper.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 剪貼簿備份項目，用於儲存每個 NSPasteboardItem 的所有 type 和 data
struct PasteboardBackupItem {
    var typeDataMap: [NSPasteboard.PasteboardType: Data]
}

/// 剪貼簿操作封裝
/// 提供備份、寫入、還原剪貼簿內容的功能
class PasteboardHelper {

    /// 備份的剪貼簿項目
    private var backupItems: [PasteboardBackupItem]?

    /// 備份目前剪貼簿內容
    /// 因為 NSPasteboardItem 在 pasteboard 被清空後就失效，
    /// 所以需要手動讀取每個 type 的 data 再存到自訂結構
    func backup() {
        let pasteboard = NSPasteboard.general

        guard let items = pasteboard.pasteboardItems else {
            backupItems = nil
            NSLog("PasteboardHelper: 剪貼簿為空，無需備份")
            return
        }

        var result: [PasteboardBackupItem] = []

        for item in items {
            var typeDataMap: [NSPasteboard.PasteboardType: Data] = [:]

            for type in item.types {
                if let data = item.data(forType: type) {
                    typeDataMap[type] = data
                }
            }

            if !typeDataMap.isEmpty {
                result.append(PasteboardBackupItem(typeDataMap: typeDataMap))
            }
        }

        backupItems = result.isEmpty ? nil : result
        NSLog("PasteboardHelper: 已備份 \(result.count) 個剪貼簿項目")
    }

    /// 將文字寫入剪貼簿
    func write(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        NSLog("PasteboardHelper: 已寫入文字到剪貼簿，長度 \(text.count)")
    }

    /// 還原備份的剪貼簿內容
    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard let items = backupItems else {
            NSLog("PasteboardHelper: 沒有備份，已清空剪貼簿")
            return
        }

        // 將備份的資料寫回剪貼簿
        var pasteboardItems: [NSPasteboardItem] = []

        for backupItem in items {
            let newItem = NSPasteboardItem()

            for (type, data) in backupItem.typeDataMap {
                newItem.setData(data, forType: type)
            }

            pasteboardItems.append(newItem)
        }

        pasteboard.writeObjects(pasteboardItems)
        backupItems = nil
        NSLog("PasteboardHelper: 已還原 \(pasteboardItems.count) 個剪貼簿項目")
    }
}
