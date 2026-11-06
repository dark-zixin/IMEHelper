import Foundation

enum CangjieDiagnostics {
    enum Operation: String {
        case dictionaryLoad
        case listLoad
        case listSave
        case listRemove
        case recoveryHelp
    }

    enum Result: String {
        case success
        case failure
        case empty
    }

    enum Reason: String {
        case none
        case emptyNotCreated
        case resourceMissing
        case resourceReadFailed
        case resourceMalformed
        case storeReadFailed
        case storeMalformed
        case storeDuplicateIdentifier
        case storeDuplicateCharacter
        case storeInvalidCharacter
        case storeInvalidCode
        case storeInvalidDate
        case storeLegacyTextMismatch
        case unsupportedVersion
        case encodeFailed
        case writeFailed
        case helpResourceMissing
        case helpOpenFailed
    }

    static func record(
        operation: Operation,
        result: Result,
        reason: Reason = .none,
        recordID: UUID? = nil,
        entryCount: Int = 0,
        characterCount: Int = 0,
        error: Error? = nil
    ) {
        let domain: String
        let code: Int
        if let error {
            let nsError = error as NSError
            switch nsError.domain {
            case NSCocoaErrorDomain, NSPOSIXErrorDomain:
                domain = nsError.domain
            default:
                domain = "unknown"
            }
            code = nsError.code
        } else {
            domain = "unknown"
            code = 0
        }

        NSLog(
            "[CangjieLookup] operation=%@ result=%@ reason=%@ recordID=%@ entryCount=%d characterCount=%d errorDomain=%@ errorCode=%d",
            operation.rawValue,
            result.rawValue,
            reason.rawValue,
            recordID?.uuidString ?? "none",
            entryCount,
            characterCount,
            domain,
            code
        )
    }
}
