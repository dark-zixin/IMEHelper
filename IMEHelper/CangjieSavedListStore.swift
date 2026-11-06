import Foundation

struct CangjieSavedEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let character: String
    let codes: [String]
    let savedAt: Date
}

enum CangjieSavedListError: Error {
    case storeReadFailed
    case storeMalformed
    case unsupportedVersion
    case encodeFailed
    case writeFailed
}

final class CangjieSavedListStore {
    private struct Header: Decodable {
        let schemaVersion: Int
    }

    private struct Snapshot: Codable {
        let schemaVersion: Int
        let entries: [CangjieSavedEntry]
    }

    private struct LegacySnapshot: Decodable {
        let schemaVersion: Int
        let entries: [LegacyEntry]
    }

    private struct LegacyEntry: Decodable {
        let id: UUID
        let text: String
        let characters: [CangjieCharacterResult]
        let createdAt: Date
    }

    private let fileURL: URL
    private(set) var entries: [CangjieSavedEntry]

    init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/IMEHelper/cangjie-list.json")

        let data: Data
        do {
            data = try Data(contentsOf: self.fileURL)
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoSuchFileError {
                entries = []
                CangjieDiagnostics.record(operation: .listLoad, result: .empty, reason: .emptyNotCreated)
                return
            }
            CangjieDiagnostics.record(operation: .listLoad, result: .failure, reason: .storeReadFailed, error: error)
            throw CangjieSavedListError.storeReadFailed
        }

        let version: Int
        do {
            version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
        } catch {
            CangjieDiagnostics.record(operation: .listLoad, result: .failure, reason: .storeMalformed, error: error)
            throw CangjieSavedListError.storeMalformed
        }

        guard version == 1 || version == 2 else {
            CangjieDiagnostics.record(operation: .listLoad, result: .failure, reason: .unsupportedVersion)
            throw CangjieSavedListError.unsupportedVersion
        }

        let loaded: [CangjieSavedEntry]
        do {
            if version == 1 {
                let legacy = try JSONDecoder().decode(LegacySnapshot.self, from: data)
                if let issue = Self.validationIssue(legacy.entries) {
                    CangjieDiagnostics.record(operation: .listLoad, result: .failure, reason: issue, entryCount: legacy.entries.count)
                    throw CangjieSavedListError.storeMalformed
                }
                loaded = Self.convert(legacy.entries)
            } else {
                loaded = try JSONDecoder().decode(Snapshot.self, from: data).entries
            }
        } catch {
            if version != 1 || !(error is CangjieSavedListError) {
                CangjieDiagnostics.record(operation: .listLoad, result: .failure, reason: .storeMalformed, error: error)
            }
            throw CangjieSavedListError.storeMalformed
        }
        if let issue = Self.validationIssue(loaded) {
            CangjieDiagnostics.record(operation: .listLoad, result: .failure, reason: issue, entryCount: loaded.count)
            throw CangjieSavedListError.storeMalformed
        }
        entries = loaded
        CangjieDiagnostics.record(operation: .listLoad, result: .success, entryCount: entries.count)
    }

    @discardableResult
    func save(_ result: CangjieCharacterResult) throws -> CangjieSavedEntry {
        if let issue = Self.validationIssue(result, allowsWhitespace: false) {
            CangjieDiagnostics.record(operation: .listSave, result: .failure, reason: issue, entryCount: entries.count)
            throw CangjieSavedListError.storeMalformed
        }
        let key = Self.rawKey(result.character)
        let existing = entries.first { Self.rawKey($0.character) == key }
        let entry = CangjieSavedEntry(id: existing?.id ?? UUID(), character: result.character, codes: result.codes, savedAt: Date())
        let proposed = [entry] + entries.filter { Self.rawKey($0.character) != key }
        try commit(proposed, operation: .listSave, recordID: entry.id, characterCount: 1)
        return entry
    }

    func remove(id: UUID) throws {
        let remaining = entries.filter { $0.id != id }
        guard remaining.count != entries.count else { return }
        try commit(remaining, operation: .listRemove, recordID: id)
    }

    private func commit(
        _ proposed: [CangjieSavedEntry],
        operation: CangjieDiagnostics.Operation,
        recordID: UUID,
        characterCount: Int = 0
    ) throws {
        if let issue = Self.validationIssue(proposed) {
            CangjieDiagnostics.record(operation: operation, result: .failure, reason: issue, recordID: recordID, entryCount: entries.count, characterCount: characterCount)
            throw CangjieSavedListError.storeMalformed
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(Snapshot(schemaVersion: 2, entries: proposed))
        } catch {
            CangjieDiagnostics.record(operation: operation, result: .failure, reason: .encodeFailed, recordID: recordID, entryCount: entries.count, characterCount: characterCount, error: error)
            throw CangjieSavedListError.encodeFailed
        }

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            CangjieDiagnostics.record(operation: operation, result: .failure, reason: .writeFailed, recordID: recordID, entryCount: entries.count, characterCount: characterCount, error: error)
            throw CangjieSavedListError.writeFailed
        }

        entries = proposed
        CangjieDiagnostics.record(operation: operation, result: .success, recordID: recordID, entryCount: entries.count, characterCount: characterCount)
    }

    private static func validationIssue(_ entries: [CangjieSavedEntry]) -> CangjieDiagnostics.Reason? {
        let ids = Set(entries.map(\.id))
        if ids.count != entries.count { return .storeDuplicateIdentifier }
        let keys = Set(entries.map { rawKey($0.character) })
        if keys.count != entries.count { return .storeDuplicateCharacter }
        for entry in entries {
            if let issue = validationIssue(CangjieCharacterResult(character: entry.character, codes: entry.codes), allowsWhitespace: false) {
                return issue
            }
            if !entry.savedAt.timeIntervalSinceReferenceDate.isFinite { return .storeInvalidDate }
        }
        return nil
    }

    private static func validationIssue(_ result: CangjieCharacterResult, allowsWhitespace: Bool) -> CangjieDiagnostics.Reason? {
        guard result.character.count == 1,
              let character = result.character.first,
              allowsWhitespace || !character.isWhitespace else { return .storeInvalidCharacter }
        return areValidCodes(result.codes) ? nil : .storeInvalidCode
    }

    private static func areValidCodes(_ codes: [String]) -> Bool {
        codes.allSatisfy { code in
            !code.isEmpty && code.utf8.allSatisfy { $0 >= 97 && $0 <= 122 }
        }
    }

    private static func validationIssue(_ entries: [LegacyEntry]) -> CangjieDiagnostics.Reason? {
        if Set(entries.map(\.id)).count != entries.count { return .storeDuplicateIdentifier }
        for entry in entries {
            if !entry.createdAt.timeIntervalSinceReferenceDate.isFinite { return .storeInvalidDate }
            for result in entry.characters {
                if let issue = validationIssue(result, allowsWhitespace: true) { return issue }
            }
            if entry.characters.map(\.character).joined().unicodeScalars.map(\.value) != rawKey(entry.text) {
                return .storeLegacyTextMismatch
            }
        }
        return nil
    }

    private static func convert(_ legacy: [LegacyEntry]) -> [CangjieSavedEntry] {
        var converted: [CangjieSavedEntry] = []
        var positions: [[UInt32]: Int] = [:]
        for oldEntry in legacy {
            for result in oldEntry.characters {
                guard let character = result.character.first, !character.isWhitespace else { continue }
                let key = rawKey(result.character)
                if let position = positions[key] {
                    let previous = converted[position]
                    let allCodes = previous.codes + result.codes.filter { !previous.codes.contains($0) }
                    converted[position] = CangjieSavedEntry(
                        id: previous.id,
                        character: previous.character,
                        codes: orderedCodes(allCodes),
                        savedAt: previous.savedAt
                    )
                } else {
                    positions[key] = converted.count
                    converted.append(CangjieSavedEntry(
                        id: UUID(),
                        character: result.character,
                        codes: orderedCodes(result.codes),
                        savedAt: oldEntry.createdAt
                    ))
                }
            }
        }
        return converted
    }

    private static func orderedCodes(_ codes: [String]) -> [String] {
        let unique = codes.reduce(into: [String]()) { result, code in
            if !result.contains(code) { result.append(code) }
        }
        return unique.filter { !$0.hasPrefix("x") } + unique.filter { $0.hasPrefix("x") }
    }

    private static func rawKey(_ character: String) -> [UInt32] {
        character.unicodeScalars.map(\.value)
    }
}
