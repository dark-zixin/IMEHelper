import Foundation

struct CangjieCharacterResult: Codable, Equatable {
    let character: String
    let codes: [String]
}

enum CangjieDictionaryError: Error {
    case resourceMissing
    case resourceReadFailed
    case resourceMalformed
}

struct CangjieDictionary {
    // 字碼表含正規等價但原始 scalar 不同的字，直接用 String 當鍵會合併三組資料。
    private let codesByCharacter: [[UInt32]: [String]]
    private static let radicalValues = Array("日月金木水火土竹戈十大中一弓人心手口尸廿山女田難卜重")

    static func load(bundle: Bundle = .main) throws -> CangjieDictionary {
        guard let resourceURL = bundle.url(forResource: "cangjie5", withExtension: "tsv") else {
            CangjieDiagnostics.record(operation: .dictionaryLoad, result: .failure, reason: .resourceMissing)
            throw CangjieDictionaryError.resourceMissing
        }
        return try CangjieDictionary(resourceURL: resourceURL)
    }

    init(resourceURL: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: resourceURL)
        } catch {
            CangjieDiagnostics.record(operation: .dictionaryLoad, result: .failure, reason: .resourceReadFailed, error: error)
            throw CangjieDictionaryError.resourceReadFailed
        }

        guard let contents = String(data: data, encoding: .utf8) else {
            CangjieDiagnostics.record(operation: .dictionaryLoad, result: .failure, reason: .resourceMalformed)
            throw CangjieDictionaryError.resourceMalformed
        }

        var indexed: [[UInt32]: [String]] = [:]
        var rowCount = 0
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty { continue }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count == 2,
                  columns[0].count == 1,
                  !columns[1].isEmpty,
                  columns[1].utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }) else {
                CangjieDiagnostics.record(operation: .dictionaryLoad, result: .failure, reason: .resourceMalformed, entryCount: rowCount)
                throw CangjieDictionaryError.resourceMalformed
            }
            let character = String(columns[0]).unicodeScalars.map(\.value)
            let code = String(columns[1])
            if !indexed[character, default: []].contains(code) {
                indexed[character, default: []].append(code)
            }
            rowCount += 1
        }
        guard rowCount > 0 else {
            CangjieDiagnostics.record(operation: .dictionaryLoad, result: .failure, reason: .resourceMalformed)
            throw CangjieDictionaryError.resourceMalformed
        }

        codesByCharacter = indexed.mapValues { codes in
            codes.filter { !$0.hasPrefix("x") } + codes.filter { $0.hasPrefix("x") }
        }
        CangjieDiagnostics.record(operation: .dictionaryLoad, result: .success, entryCount: rowCount, characterCount: indexed.count)
    }

    func lookup(_ text: String) -> [CangjieCharacterResult] {
        text.map { character in
            let original = String(character)
            return CangjieCharacterResult(character: original, codes: codesByCharacter[original.unicodeScalars.map(\.value)] ?? [])
        }
    }

    static func radicals(for code: String) -> String {
        String(code.lowercased().utf8.compactMap { byte in
            guard byte >= 97, byte <= 122 else { return nil }
            return radicalValues[Int(byte - 97)]
        })
    }
}
