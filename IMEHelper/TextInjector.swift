//
//  TextInjector.swift
//  IMEHelper
//
//  Created by TUNG CHI KUO on 2026/3/31.
//

import Cocoa

/// 可供介面判斷的送出失敗原因
enum InjectionFailureReason: String {
    case clipboardSnapshotIncomplete
    case writeFailed
    case readbackMismatch
    case targetTerminated
    case activationRejected
    case frontmostTimeout
    case clipboardChangedBeforePaste
    case eventCreationFailed
}

/// 文字送出的終止結果
enum InjectionResult {
    case dispatchedUnconfirmed
    case recoverableFailure(InjectionFailureReason)
    case orphaned(InjectionFailureReason)
    case busyRejected
}

/// 透過剪貼簿及模擬 Cmd+V 將文字送回目標 App
@MainActor
final class TextInjector {

    private enum Mode: String {
        case restorePreviousClipboard
        case keepSubmittedText
    }

    private enum Phase: String {
        case started
        case clipboardPrepared
        case activatingTarget
        case waitingForFrontmost
        case dispatched
        case stabilizing
    }

    private struct InjectionTransaction {
        let id: UUID
        let text: String
        let targetPID: pid_t
        let mode: Mode
        let snapshot: PasteboardSnapshot
        let startedAt: ContinuousClock.Instant
        var injectedChangeCount: Int?
        var phase: Phase
    }

    private let pasteboardHelper = PasteboardHelper()
    private let frontmostTimeout: Duration = .milliseconds(1_500)
    private let frontmostPollInterval: Duration = .milliseconds(30)
    private let pasteStabilizationWindow: Duration = .seconds(1)
    private let slowTransactionThreshold: Duration = .seconds(3)
    private let clock = ContinuousClock()

    private var activeTransaction: InjectionTransaction?

    var isActive: Bool {
        activeTransaction != nil
    }

    /// 將文字送回目標 App。事件已分派不等於目標 App 已確認插入文字。
    func inject(
        text: String,
        targetPID: pid_t,
        keepSubmittedText: Bool,
        completion: @escaping (InjectionResult) -> Void
    ) {
        guard activeTransaction == nil else {
            log(
                transactionID: nil,
                phase: .started,
                reason: "busyRejected",
                mode: nil,
                targetPID: targetPID,
                result: "busyRejected"
            )
            completion(.busyRejected)
            return
        }

        guard let targetApp = NSRunningApplication(processIdentifier: targetPID),
              !targetApp.isTerminated else {
            log(
                transactionID: nil,
                phase: .started,
                reason: InjectionFailureReason.targetTerminated.rawValue,
                mode: nil,
                targetPID: targetPID,
                result: "orphaned"
            )
            completion(.orphaned(.targetTerminated))
            return
        }

        let transaction = InjectionTransaction(
            id: UUID(),
            text: text,
            targetPID: targetPID,
            mode: keepSubmittedText ? .keepSubmittedText : .restorePreviousClipboard,
            snapshot: pasteboardHelper.makeSnapshot(),
            startedAt: clock.now,
            injectedChangeCount: nil,
            phase: .started
        )
        activeTransaction = transaction
        log(transaction: transaction, reason: "none", result: "started")

        guard transaction.snapshot.isComplete else {
            finishFailure(
                transactionID: transaction.id,
                reason: .clipboardSnapshotIncomplete,
                orphaned: false,
                completion: completion
            )
            return
        }

        let writeResult = pasteboardHelper.write(text: text)
        guard updateTransaction(transaction.id, phase: .clipboardPrepared, changeCount: writeResult.changeCount) else {
            logStaleCallback(transactionID: transaction.id, targetPID: targetPID)
            return
        }

        guard writeResult.didSetString else {
            finishFailure(transactionID: transaction.id, reason: .writeFailed, orphaned: false, completion: completion)
            return
        }

        guard writeResult.readbackMatches else {
            finishFailure(transactionID: transaction.id, reason: .readbackMismatch, orphaned: false, completion: completion)
            return
        }

        guard updateTransaction(transaction.id, phase: .activatingTarget) else {
            logStaleCallback(transactionID: transaction.id, targetPID: targetPID)
            return
        }

        guard targetApp.activate(options: []) else {
            let targetEnded = targetApp.isTerminated
            finishFailure(
                transactionID: transaction.id,
                reason: targetEnded ? .targetTerminated : .activationRejected,
                orphaned: targetEnded,
                completion: completion
            )
            return
        }

        guard updateTransaction(transaction.id, phase: .waitingForFrontmost) else {
            logStaleCallback(transactionID: transaction.id, targetPID: targetPID)
            return
        }

        waitForTargetToBecomeFrontmost(
            transactionID: transaction.id,
            deadline: clock.now.advanced(by: frontmostTimeout),
            completion: completion
        )
    }

    /// App 結束時，只在剪貼簿仍由本交易持有的情況下還原。
    func prepareForTermination() {
        guard let transaction = activeTransaction else { return }

        let pasteWasDispatched = transaction.phase == .stabilizing
        let shouldRestore = transaction.mode == .restorePreviousClipboard || !pasteWasDispatched
        if shouldRestore,
           let expectedChangeCount = transaction.injectedChangeCount,
            pasteboardHelper.changeCount == expectedChangeCount {
            if !pasteboardHelper.restore(transaction.snapshot) {
                _ = pasteboardHelper.write(text: transaction.text)
            }
        }

        activeTransaction = nil
    }

    private func waitForTargetToBecomeFrontmost(
        transactionID: UUID,
        deadline: ContinuousClock.Instant,
        completion: @escaping (InjectionResult) -> Void
    ) {
        guard let transaction = currentTransaction(transactionID) else {
            logStaleCallback(transactionID: transactionID, targetPID: nil)
            return
        }

        guard let app = NSRunningApplication(processIdentifier: transaction.targetPID),
              !app.isTerminated else {
            finishFailure(transactionID: transactionID, reason: .targetTerminated, orphaned: true, completion: completion)
            return
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier == transaction.targetPID {
            dispatchPaste(transactionID: transactionID, completion: completion)
            return
        }

        guard clock.now < deadline else {
            finishFailure(transactionID: transactionID, reason: .frontmostTimeout, orphaned: false, completion: completion)
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.frontmostPollInterval ?? .milliseconds(30))
            self?.waitForTargetToBecomeFrontmost(
                transactionID: transactionID,
                deadline: deadline,
                completion: completion
            )
        }
    }

    private func dispatchPaste(
        transactionID: UUID,
        completion: @escaping (InjectionResult) -> Void
    ) {
        guard let transaction = currentTransaction(transactionID) else {
            logStaleCallback(transactionID: transactionID, targetPID: nil)
            return
        }

        guard let app = NSRunningApplication(processIdentifier: transaction.targetPID),
              !app.isTerminated else {
            finishFailure(transactionID: transactionID, reason: .targetTerminated, orphaned: true, completion: completion)
            return
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == transaction.targetPID else {
            finishFailure(transactionID: transactionID, reason: .frontmostTimeout, orphaned: false, completion: completion)
            return
        }

        guard pasteboardHelper.contains(text: transaction.text) else {
            finishFailure(
                transactionID: transactionID,
                reason: .clipboardChangedBeforePaste,
                orphaned: false,
                completion: completion
            )
            return
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            finishFailure(transactionID: transactionID, reason: .eventCreationFailed, orphaned: false, completion: completion)
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        guard updateTransaction(transactionID, phase: .dispatched) else {
            logStaleCallback(transactionID: transactionID, targetPID: transaction.targetPID)
            return
        }

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        guard updateTransaction(transactionID, phase: .stabilizing),
              let updatedTransaction = currentTransaction(transactionID) else {
            logStaleCallback(transactionID: transactionID, targetPID: transaction.targetPID)
            return
        }
        log(transaction: updatedTransaction, reason: "none", result: "pending")

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: self?.pasteStabilizationWindow ?? .seconds(1))
            self?.finishDispatched(transactionID: transactionID, completion: completion)
        }
    }

    private func finishDispatched(
        transactionID: UUID,
        completion: @escaping (InjectionResult) -> Void
    ) {
        guard let transaction = currentTransaction(transactionID) else {
            logStaleCallback(transactionID: transactionID, targetPID: nil)
            return
        }

        var reason = "none"
        if transaction.mode == .restorePreviousClipboard,
           let expectedChangeCount = transaction.injectedChangeCount {
            if pasteboardHelper.changeCount == expectedChangeCount {
                if !pasteboardHelper.restore(transaction.snapshot) {
                    reason = keepSubmittedTextAfterRestoreFailure(transaction)
                }
            } else {
                reason = "restoreSkippedExternalChange"
            }
        }

        finish(transaction: transaction, reason: reason, result: "dispatchedUnconfirmed")
        completion(.dispatchedUnconfirmed)
    }

    private func finishFailure(
        transactionID: UUID,
        reason: InjectionFailureReason,
        orphaned: Bool,
        completion: @escaping (InjectionResult) -> Void
    ) {
        guard let transaction = currentTransaction(transactionID) else {
            logStaleCallback(transactionID: transactionID, targetPID: nil)
            return
        }

        var terminalReason = reason.rawValue
        if let expectedChangeCount = transaction.injectedChangeCount,
           pasteboardHelper.changeCount == expectedChangeCount {
            if !pasteboardHelper.restore(transaction.snapshot) {
                terminalReason += "+\(keepSubmittedTextAfterRestoreFailure(transaction))"
            }
        } else if transaction.injectedChangeCount != nil {
            terminalReason += "+restoreSkippedExternalChange"
        }

        let terminalResult = orphaned ? "orphaned" : "recoverableFailure"
        finish(transaction: transaction, reason: terminalReason, result: terminalResult)
        completion(orphaned ? .orphaned(reason) : .recoverableFailure(reason))
    }

    /// 還原失敗時至少保留本次文字，避免剪貼簿落成空白或半成品。
    private func keepSubmittedTextAfterRestoreFailure(_ transaction: InjectionTransaction) -> String {
        let result = pasteboardHelper.write(text: transaction.text)
        return result.didSetString && result.readbackMatches
            ? "restoreFailedKeptSubmittedText"
            : "restoreFailedFallbackWriteFailed"
    }

    private func finish(transaction: InjectionTransaction, reason: String, result: String) {
        guard activeTransaction?.id == transaction.id else {
            logStaleCallback(transactionID: transaction.id, targetPID: transaction.targetPID)
            return
        }

        activeTransaction = nil
        log(transaction: transaction, reason: reason, result: result)

        let elapsed = transaction.startedAt.duration(to: clock.now)
        if elapsed > slowTransactionThreshold {
            log(
                transactionID: transaction.id,
                phase: transaction.phase,
                reason: "slowTransaction",
                mode: transaction.mode,
                targetPID: transaction.targetPID,
                expectedChangeCount: transaction.injectedChangeCount,
                result: "warning",
                startedAt: transaction.startedAt
            )
        }
    }

    private func currentTransaction(_ id: UUID) -> InjectionTransaction? {
        guard let transaction = activeTransaction, transaction.id == id else { return nil }
        return transaction
    }

    @discardableResult
    private func updateTransaction(_ id: UUID, phase: Phase, changeCount: Int? = nil) -> Bool {
        guard var transaction = currentTransaction(id) else { return false }
        transaction.phase = phase
        if let changeCount {
            transaction.injectedChangeCount = changeCount
        }
        activeTransaction = transaction
        return true
    }

    private func logStaleCallback(transactionID: UUID, targetPID: pid_t?) {
        log(
            transactionID: transactionID,
            phase: nil,
            reason: "staleCallback",
            mode: nil,
            targetPID: targetPID,
            result: "ignored"
        )
    }

    private func log(transaction: InjectionTransaction, reason: String, result: String) {
        log(
            transactionID: transaction.id,
            phase: transaction.phase,
            reason: reason,
            mode: transaction.mode,
            targetPID: transaction.targetPID,
            expectedChangeCount: transaction.injectedChangeCount,
            result: result,
            startedAt: transaction.startedAt
        )
    }

    private func log(
        transactionID: UUID?,
        phase: Phase?,
        reason: String,
        mode: Mode?,
        targetPID: pid_t?,
        expectedChangeCount: Int? = nil,
        result: String,
        startedAt: ContinuousClock.Instant? = nil
    ) {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
        let elapsedMilliseconds: Int
        if let startedAt {
            let components = startedAt.duration(to: clock.now).components
            elapsedMilliseconds = Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
        } else {
            elapsedMilliseconds = 0
        }

        NSLog(
            "[Injection] txID=%@ phase=%@ reason=%@ mode=%@ targetPID=%d frontmostPID=%d expectedChangeCount=%ld observedChangeCount=%ld elapsedMS=%ld result=%@",
            transactionID?.uuidString ?? "none",
            phase?.rawValue ?? "none",
            reason,
            mode?.rawValue ?? "none",
            targetPID ?? -1,
            frontmostPID,
            expectedChangeCount ?? -1,
            pasteboardHelper.changeCount,
            elapsedMilliseconds,
            result
        )
    }
}
