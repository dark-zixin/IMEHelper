import Cocoa

private class CangjieFlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class CangjieActionButton: NSButton {
    var handler: (() -> Void)?

    init(_ title: String, identifier: String, handler: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        self.handler = handler
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        setAccessibilityIdentifier(identifier)
        target = self
        action = #selector(invoke)
        isBordered = false
        bezelStyle = .inline
        font = .systemFont(ofSize: 12)
        contentTintColor = .controlAccentColor
    }

    required init?(coder: NSCoder) { nil }
    @objc private func invoke() { handler?() }
}

private final class CangjieCodeRow: CangjieFlippedView {
    let characterLabel = NSTextField(labelWithString: "")
    let roots = CangjieLookupTextView()
    let button: CangjieActionButton?
    private let codes: [String]
    private let rootFont: NSFont
    private let minimumHeight: CGFloat
    private let multiline: Bool
    private let unknown: String
    private let actionWidth: CGFloat

    init(result: CangjieCharacterResult, identifier: String, recent: Bool = false,
         multiline: Bool = false, actionTitle: String? = nil, alternateActionTitles: [String] = [], unknown: String,
         action: (() -> Void)? = nil) {
        codes = result.codes
        rootFont = .systemFont(ofSize: recent ? 14 : 15)
        minimumHeight = multiline ? 40 : (recent ? 26 : 30)
        self.multiline = multiline
        self.unknown = unknown
        if let actionTitle, let action {
            let actionButton = CangjieActionButton(actionTitle, identifier: identifier + "-action", handler: action)
            actionWidth = ceil(([actionTitle] + alternateActionTitles).reduce(CGFloat(32)) { width, title in
                actionButton.title = title
                return max(width, actionButton.cell?.cellSize.width ?? 0)
            })
            actionButton.title = actionTitle
            button = actionButton
        } else {
            button = nil
            actionWidth = 0
        }
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(identifier)
        characterLabel.stringValue = result.character
        characterLabel.font = .systemFont(ofSize: recent ? 18 : 21, weight: .medium)
        characterLabel.textColor = .labelColor
        addSubview(characterLabel)
        roots.isEditable = false
        roots.isSelectable = true
        roots.isRichText = false
        roots.drawsBackground = false
        roots.isVerticallyResizable = false
        roots.isHorizontallyResizable = false
        roots.textContainerInset = .zero
        roots.textContainer?.lineFragmentPadding = 0
        roots.font = rootFont
        roots.textColor = .labelColor
        roots.identifier = NSUserInterfaceItemIdentifier(identifier + "-roots")
        roots.setAccessibilityIdentifier(identifier + "-roots")
        addSubview(roots)
        if let button { addSubview(button) }
    }

    required init?(coder: NSCoder) { nil }

    @discardableResult
    func arrange(width: CGFloat) -> CGFloat {
        let available = max(40, width - 36 - (button == nil ? 0 : actionWidth + 2))
        let groups = codes.map { CangjieDictionary.radicals(for: $0) }
        let joined = groups.joined(separator: "／")
        let text = groups.isEmpty ? unknown : ((multiline || (joined as NSString).size(withAttributes: [.font: rootFont]).width > available) ? groups.joined(separator: "\n") : joined)
        roots.string = text
        let textHeight = ceil((text as NSString).boundingRect(with: NSSize(width: available, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: rootFont]).height)
        let height = max(minimumHeight, textHeight + 6)
        setFrameSize(NSSize(width: width, height: height))
        characterLabel.frame = NSRect(x: 4, y: 2, width: 30, height: 25)
        roots.frame = NSRect(x: 36, y: 3, width: available, height: height - 6)
        roots.textContainer?.containerSize = NSSize(width: available, height: .greatestFiniteMagnitude)
        button?.frame = NSRect(x: width - actionWidth, y: 1, width: actionWidth, height: 26)
        return height
    }
}

private final class CangjieDeleteBadge: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.withAlphaComponent(0.2).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
        ("×" as NSString).draw(at: NSPoint(x: 3, y: 0), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemRed])
    }
}

private final class CangjieConfirmationView: CangjieFlippedView {
    let panel = CangjieFlippedView()
    let title = NSTextField(labelWithString: "")
    let message = NSTextField(wrappingLabelWithString: "")
    let cancelButton: CangjieActionButton
    let confirmButton: CangjieActionButton

    init(character: String, localize: (String) -> String, cancel: @escaping () -> Void, confirm: @escaping () -> Void) {
        cancelButton = CangjieActionButton(localize("lookup.cancel"), identifier: "cangjie-cancel-delete", handler: cancel)
        confirmButton = CangjieActionButton(localize("lookup.delete"), identifier: "cangjie-confirm-delete", handler: confirm)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("cangjie-delete-confirmation")
        setAccessibilityRole(.group)
        setAccessibilityLabel(localize("lookup.delete_title"))
        panel.wantsLayer = true
        panel.layer?.cornerRadius = 9
        panel.layer?.borderWidth = 1
        addSubview(panel)
        title.stringValue = String(format: localize("lookup.delete_character"), character)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        message.stringValue = localize("lookup.delete_message")
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        cancelButton.isBordered = true
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\r"
        confirmButton.isBordered = true
        confirmButton.bezelStyle = .rounded
        confirmButton.contentTintColor = .systemRed
        [title, message, cancelButton, confirmButton].forEach(panel.addSubview)
    }

    required init?(coder: NSCoder) { nil }
    override func cancelOperation(_ sender: Any?) { cancelButton.performClick(sender) }
    override func mouseDown(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()
    }

    override func layout() {
        super.layout()
        panel.frame = NSRect(x: (bounds.width - 212) / 2, y: max(4, (bounds.height - 118) / 2), width: 212, height: 118)
        panel.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.layer?.borderColor = NSColor.separatorColor.cgColor
        title.frame = NSRect(x: 12, y: 12, width: 188, height: 22)
        message.frame = NSRect(x: 12, y: 37, width: 188, height: 32)
        cancelButton.frame = NSRect(x: 12, y: 79, width: 80, height: 28)
        confirmButton.frame = NSRect(x: 120, y: 79, width: 80, height: 28)
    }
}

final class CangjieLookupContentView: NSView, NSTextViewDelegate {
    override var isFlipped: Bool { true }

    let input = CangjieLookupTextView()
    var preferredHeightDidChange: ((CGFloat) -> Void)?
    var pinnedDidChange: ((Bool) -> Void)?
    var expandedDidChange: ((Bool) -> Void)?
    var retry: (() -> Void)?
    var recoveryHelp: (() -> Void)?
    private(set) var preferredHeight: CGFloat = 138
    private(set) var isExpanded = false
    private var isManaging = false
    private var pinned = false
    private var selectedID: UUID?
    private var pendingDeleteID: UUID?
    private var dictionary: CangjieDictionary?
    private var store: CangjieSavedListStore?
    private var resourceIssue: String?
    private var storeIssue: String?
    private var results: [CangjieCharacterResult] = []
    private let localize: (String) -> String
    private let title = NSTextField(labelWithString: "")
    private let pin: CangjieActionButton
    private let disclosure: CangjieActionButton
    private let manage: CangjieActionButton
    private let retryButton: CangjieActionButton
    private let recoveryButton: CangjieActionButton
    private let status = NSTextField(wrappingLabelWithString: "")
    private let recentTitle = NSTextField(labelWithString: "")
    private let otherTitle = NSTextField(labelWithString: "")
    private let emptyQuery = NSTextField(labelWithString: "")
    private let emptySaved = NSTextField(wrappingLabelWithString: "")
    private let emptyOther = NSTextField(labelWithString: "")
    private let inputScroll = NSScrollView()
    private let queryScroll = NSScrollView()
    private let recentScroll = NSScrollView()
    private let otherScroll = NSScrollView()
    private let detailScroll = NSScrollView()
    private let queryDocument = CangjieFlippedView()
    private let recentDocument = CangjieFlippedView()
    private let otherDocument = CangjieFlippedView()
    private let detailDocument = CangjieFlippedView()
    private var queryRows: [CangjieCodeRow] = []
    private var recentRows: [CangjieCodeRow] = []
    private var otherButtons: [CangjieActionButton] = []
    private var detailRow: CangjieCodeRow?
    private var confirmation: CangjieConfirmationView?
    private var headerY: CGFloat = 108

    init(localize: @escaping (String) -> String) {
        self.localize = localize
        pin = CangjieActionButton(localize("lookup.pin"), identifier: "cangjie-pin", handler: {})
        disclosure = CangjieActionButton("", identifier: "cangjie-saved-toggle", handler: {})
        manage = CangjieActionButton(localize("lookup.manage"), identifier: "cangjie-manage", handler: {})
        retryButton = CangjieActionButton(localize("lookup.retry"), identifier: "cangjie-retry", handler: {})
        recoveryButton = CangjieActionButton(localize("lookup.recovery_help"), identifier: "cangjie-recovery-help", handler: {})
        super.init(frame: NSRect(x: 0, y: 0, width: 244, height: 138))
        autoresizingMask = [.width, .height]
        title.stringValue = localize("lookup.title")
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = .secondaryLabelColor
        pin.font = .systemFont(ofSize: 11)
        pin.setButtonType(.toggle)
        pin.handler = { [weak self] in
            guard let self else { return }
            self.setPinned(!self.pinned)
            self.pinnedDidChange?(self.pinned)
        }
        disclosure.alignment = .left
        disclosure.contentTintColor = .secondaryLabelColor
        disclosure.handler = { [weak self] in
            guard let self else { return }
            self.setExpanded(!self.isExpanded)
            self.expandedDidChange?(self.isExpanded)
        }
        manage.handler = { [weak self] in
            guard let self else { return }
            self.isManaging.toggle()
            self.rebuildSaved()
        }
        retryButton.handler = { [weak self] in self?.retry?() }
        recoveryButton.handler = { [weak self] in self?.recoveryHelp?() }
        status.font = .systemFont(ofSize: 11)
        status.textColor = .systemRed
        status.identifier = NSUserInterfaceItemIdentifier("cangjie-status")
        for label in [recentTitle, otherTitle, emptyQuery, emptySaved, emptyOther] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }
        recentTitle.stringValue = localize("lookup.recent")
        otherTitle.stringValue = localize("lookup.other")
        emptyQuery.stringValue = localize("lookup.empty_input")
        emptyOther.stringValue = localize("lookup.empty_other")
        emptySaved.identifier = NSUserInterfaceItemIdentifier("cangjie-empty-saved")
        emptyOther.identifier = NSUserInterfaceItemIdentifier("cangjie-empty-other")
        input.delegate = self
        input.identifier = NSUserInterfaceItemIdentifier("cangjie-input")
        input.setAccessibilityIdentifier("cangjie-input")
        input.setAccessibilityLabel(localize("lookup.input"))
        input.isRichText = false
        input.allowsUndo = true
        input.isAutomaticQuoteSubstitutionEnabled = false
        input.isAutomaticDashSubstitutionEnabled = false
        input.isAutomaticTextReplacementEnabled = false
        input.font = .systemFont(ofSize: 16)
        input.textColor = .labelColor
        input.backgroundColor = .textBackgroundColor
        input.textContainerInset = NSSize(width: 6, height: 4)
        input.textContainer?.lineFragmentPadding = 0
        input.isVerticallyResizable = true
        input.isHorizontallyResizable = false
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        input.compositionDidChange = { [weak self] in self?.updateQuery() }
        inputScroll.documentView = input
        inputScroll.borderType = .bezelBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        configure(queryScroll, document: queryDocument, identifier: "cangjie-results")
        configure(recentScroll, document: recentDocument, identifier: "cangjie-recent")
        configure(otherScroll, document: otherDocument, identifier: "cangjie-other")
        configure(detailScroll, document: detailDocument, identifier: "cangjie-detail")
        [title, pin, inputScroll, queryScroll, disclosure, manage, recentTitle, recentScroll,
         otherTitle, otherScroll, detailScroll, status, retryButton, recoveryButton].forEach(addSubview)
        queryDocument.addSubview(emptyQuery)
        recentDocument.addSubview(emptySaved)
        otherDocument.addSubview(emptyOther)
        updateQuery()
        rebuildSaved()
    }

    required init?(coder: NSCoder) { nil }

    private func configure(_ scroll: NSScrollView, document: NSView, identifier: String) {
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.identifier = NSUserInterfaceItemIdentifier(identifier)
        scroll.setAccessibilityIdentifier(identifier)
    }

    func setResources(dictionary: CangjieDictionary?, store: CangjieSavedListStore?, resourceIssue: String?, storeIssue: String?) {
        self.dictionary = dictionary
        self.store = store
        self.resourceIssue = resourceIssue
        self.storeIssue = storeIssue
        setStatus(resourceIssue ?? storeIssue)
        updateQuery()
        rebuildSaved()
    }

    func setPinned(_ value: Bool) {
        pinned = value
        pin.state = value ? .on : .off
        pin.contentTintColor = value ? .controlAccentColor : .secondaryLabelColor
    }

    func setExpanded(_ value: Bool) {
        isExpanded = value
        if !value { isManaging = false }
        rebuildSaved()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === input else { return }
        updateQuery()
    }

    private func updateQuery() {
        guard !input.isComposing else {
            queryRows.forEach { $0.button?.isEnabled = false }
            return
        }
        results = dictionary?.lookup(input.string).filter { !$0.character.allSatisfy(\.isWhitespace) } ?? []
        queryRows.forEach { $0.removeFromSuperview() }
        queryRows = results.enumerated().map { index, result in
            let row = CangjieCodeRow(result: result, identifier: "query-\(index)", actionTitle: localize("lookup.save"), alternateActionTitles: [localize("lookup.saved_short")], unknown: localize("lookup.not_found")) { [weak self] in self?.saveCharacter(result) }
            row.button?.isEnabled = store != nil && pendingDeleteID == nil
            row.button?.setAccessibilityLabel(String(format: localize("lookup.save_character"), result.character))
            queryDocument.addSubview(row)
            return row
        }
        emptyQuery.stringValue = resourceIssue ?? localize("lookup.empty_input")
        emptyQuery.isHidden = !queryRows.isEmpty
        refreshLayout()
    }

    private func saveCharacter(_ result: CangjieCharacterResult) {
        guard let store, dictionary != nil, !input.isComposing, pendingDeleteID == nil else { return }
        do {
            try store.save(result)
            setStatus(resourceIssue ?? storeIssue)
            rebuildSaved()
            queryRows.filter { $0.characterLabel.stringValue.unicodeScalars.map(\.value) == result.character.unicodeScalars.map(\.value) }
                .forEach {
                    $0.button?.title = localize("lookup.saved_short")
                    $0.button?.setAccessibilityLabel(String(format: localize("lookup.saved_character"), result.character))
                }
        } catch {
            setStatus(localize("lookup.save_error"))
        }
    }

    private func rebuildSaved() {
        recentRows.forEach { $0.removeFromSuperview() }
        otherButtons.forEach { $0.removeFromSuperview() }
        detailRow?.removeFromSuperview()
        recentRows = []
        otherButtons = []
        detailRow = nil
        let entries = store?.entries ?? []
        if let selectedID, !entries.dropFirst(3).contains(where: { $0.id == selectedID }) { self.selectedID = nil }
        let savedSummary = store == nil ? localize("lookup.saved_unavailable") : "\(localize("lookup.saved"))  \(entries.count)"
        disclosure.title = "\(isExpanded ? "⌄" : "›")  \(savedSummary)"
        disclosure.setAccessibilityLabel(localize(isExpanded ? "lookup.collapse_saved" : "lookup.expand_saved"))
        manage.title = localize(isManaging ? "lookup.done" : "lookup.manage")
        manage.isEnabled = store != nil
        for entry in entries.prefix(3) {
            let row = CangjieCodeRow(result: CangjieCharacterResult(character: entry.character, codes: entry.codes), identifier: "recent-\(entry.id.uuidString)", recent: true, actionTitle: isManaging ? "×" : nil, unknown: localize("lookup.not_found"), action: { [weak self] in self?.askToDelete(entry) })
            row.button?.contentTintColor = .systemRed
            row.button?.setAccessibilityLabel(String(format: localize("lookup.delete_character"), entry.character))
            recentDocument.addSubview(row)
            recentRows.append(row)
        }
        for entry in entries.dropFirst(3) {
            let button = CangjieActionButton(entry.character, identifier: "other-\(entry.id.uuidString)") { [weak self] in
                guard let self else { return }
                if self.isManaging { self.askToDelete(entry) }
                else { self.selectedID = entry.id; self.rebuildSaved() }
            }
            button.font = .systemFont(ofSize: 17)
            button.contentTintColor = selectedID == entry.id ? .controlAccentColor : .labelColor
            button.setAccessibilityLabel(isManaging ? String(format: localize("lookup.delete_character"), entry.character) : entry.character)
            if isManaging {
                let badge = CangjieDeleteBadge(frame: NSRect(x: 24, y: 14, width: 14, height: 14))
                button.addSubview(badge)
            }
            otherDocument.addSubview(button)
            otherButtons.append(button)
        }
        if let entry = entries.first(where: { $0.id == selectedID }) {
            let row = CangjieCodeRow(result: CangjieCharacterResult(character: entry.character, codes: entry.codes), identifier: "selected", recent: true, multiline: true, unknown: localize("lookup.not_found"))
            detailDocument.addSubview(row)
            detailRow = row
        }
        emptySaved.stringValue = store == nil ? localize("lookup.saved_unavailable") : localize("lookup.empty_saved")
        emptySaved.isHidden = !entries.isEmpty
        emptyOther.isHidden = store == nil || !otherButtons.isEmpty
        refreshLayout()
    }

    private func askToDelete(_ entry: CangjieSavedEntry) {
        guard pendingDeleteID == nil, store != nil else { return }
        pendingDeleteID = entry.id
        let overlay = CangjieConfirmationView(character: entry.character, localize: localize, cancel: { [weak self] in self?.cancelDeletion() }, confirm: { [weak self] in self?.confirmDeletion() })
        confirmation = overlay
        addSubview(overlay)
        input.isEditable = false
        setControlsEnabled(false)
        refreshLayout()
        window?.makeFirstResponder(overlay.cancelButton)
    }

    func cancelDeletion() {
        pendingDeleteID = nil
        confirmation?.removeFromSuperview()
        confirmation = nil
        input.isEditable = true
        setControlsEnabled(true)
        updateQuery()
        window?.makeFirstResponder(input)
    }

    private func confirmDeletion() {
        guard let id = pendingDeleteID, let store else { return }
        do {
            try store.remove(id: id)
            cancelDeletion()
            setStatus(resourceIssue ?? storeIssue)
            rebuildSaved()
        } catch {
            cancelDeletion()
            setStatus(localize("lookup.delete_error"))
        }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        [pin, disclosure, retryButton, recoveryButton].forEach { $0.isEnabled = enabled }
        manage.isEnabled = enabled && store != nil
        recentRows.forEach { $0.button?.isEnabled = enabled }
        otherButtons.forEach { $0.isEnabled = enabled }
        queryRows.forEach { $0.button?.isEnabled = enabled && store != nil && !input.isComposing }
    }

    private func setStatus(_ message: String?) {
        status.stringValue = message ?? ""
        status.isHidden = message == nil
        retryButton.isHidden = resourceIssue == nil && storeIssue == nil
        recoveryButton.isHidden = storeIssue == nil
        refreshLayout()
    }

    func showRecoveryHelpFailure() {
        setStatus(localize("lookup.recovery_help_error"))
    }

    private func refreshLayout() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        needsDisplay = true
    }

    @discardableResult
    private func arrange(_ rows: [CangjieCodeRow], in document: NSView, width: CGFloat, minimum: CGFloat = 0) -> CGFloat {
        var y: CGFloat = 0
        for row in rows {
            let height = row.arrange(width: width)
            row.setFrameOrigin(NSPoint(x: 0, y: y))
            y += height
        }
        document.setFrameSize(NSSize(width: width, height: max(minimum, y)))
        return max(minimum, y)
    }

    override func layout() {
        super.layout()
        let width = max(244, bounds.width), innerWidth = width - 20
        title.frame = NSRect(x: 30, y: 5, width: width - 100, height: 18)
        pin.frame = NSRect(x: width - 58, y: 3, width: 52, height: 22)
        inputScroll.frame = NSRect(x: 10, y: 36, width: innerWidth, height: 28)
        input.setFrameSize(NSSize(width: inputScroll.contentSize.width, height: max(28, input.frame.height)))
        input.textContainer?.containerSize = NSSize(width: inputScroll.contentSize.width - 12, height: .greatestFiniteMagnitude)
        let queryHeight = arrange(queryRows, in: queryDocument, width: innerWidth, minimum: 30)
        let baseQueryHeight = min(90, queryHeight)
        let detailHeight: CGFloat = detailRow == nil ? 0 : 40
        let statusWidth = innerWidth
        let feedbackTextHeight: CGFloat = status.isHidden ? 0 : max(32, ceil((status.stringValue as NSString).boundingRect(with: NSSize(width: statusWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [.font: NSFont.systemFont(ofSize: 11)]).height) + 10)
        let feedbackHeight = feedbackTextHeight + (retryButton.isHidden && recoveryButton.isHidden ? 0 : 28)
        let desiredHeight = 108 + (baseQueryHeight - 30) + (isExpanded ? 224 + detailHeight : 30) + feedbackHeight
        let extra = max(0, bounds.height - desiredHeight)
        queryScroll.frame = NSRect(x: 10, y: 72, width: innerWidth, height: baseQueryHeight + extra)
        emptyQuery.frame = NSRect(x: 4, y: 5, width: innerWidth - 8, height: 22)
        headerY = 108 + (baseQueryHeight - 30) + extra
        disclosure.frame = NSRect(x: 8, y: headerY + 2, width: width - (isExpanded ? 70 : 16), height: 26)
        manage.frame = NSRect(x: width - 58, y: headerY + 3, width: 48, height: 24)
        [manage, recentTitle, recentScroll, otherTitle, otherScroll].forEach { $0.isHidden = !isExpanded }
        detailScroll.isHidden = !isExpanded || detailRow == nil
        recentTitle.frame = NSRect(x: 13, y: headerY + 32, width: innerWidth, height: 16)
        recentScroll.frame = NSRect(x: 10, y: headerY + 50, width: innerWidth, height: 78)
        arrange(recentRows, in: recentDocument, width: innerWidth, minimum: 78)
        emptySaved.frame = NSRect(x: 4, y: 5, width: innerWidth - 8, height: 60)
        otherTitle.frame = NSRect(x: 13, y: headerY + 132, width: innerWidth, height: 16)
        otherScroll.frame = NSRect(x: 10, y: headerY + 153, width: innerWidth, height: 60)
        let cellWidth = floor((innerWidth - 12) / 5)
        for (index, button) in otherButtons.enumerated() {
            button.frame = NSRect(x: CGFloat(index % 5) * cellWidth + 1, y: CGFloat(index / 5) * 30 + 2, width: cellWidth - 4, height: 26)
            button.subviews.first?.setFrameOrigin(NSPoint(x: button.bounds.width - 14, y: 14))
        }
        otherDocument.setFrameSize(NSSize(width: innerWidth, height: max(60, CGFloat((otherButtons.count + 4) / 5) * 30)))
        emptyOther.frame = NSRect(x: 4, y: 6, width: innerWidth - 8, height: 20)
        detailScroll.frame = NSRect(x: 10, y: headerY + 220, width: innerWidth, height: detailHeight)
        if let detailRow { arrange([detailRow], in: detailDocument, width: innerWidth, minimum: 40) }
        let feedbackY = desiredHeight - feedbackHeight + extra
        status.frame = NSRect(x: 10, y: feedbackY + 3, width: statusWidth, height: max(0, feedbackTextHeight - 6))
        let retryWidth = ceil(max(42, retryButton.cell?.cellSize.width ?? 0))
        retryButton.frame = NSRect(x: 10, y: feedbackY + feedbackTextHeight, width: retryWidth, height: 26)
        recoveryButton.frame = NSRect(x: 18 + retryWidth, y: feedbackY + feedbackTextHeight,
                                     width: ceil(max(42, recoveryButton.cell?.cellSize.width ?? 0)), height: 26)
        confirmation?.frame = NSRect(x: 0, y: 28, width: width, height: bounds.height - 28)
        if abs(preferredHeight - desiredHeight) > 0.1 {
            preferredHeight = desiredHeight
            preferredHeightDidChange?(desiredHeight)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        let lines = NSBezierPath()
        lines.move(to: NSPoint(x: 0, y: 28)); lines.line(to: NSPoint(x: bounds.width, y: 28))
        lines.move(to: NSPoint(x: 10, y: headerY)); lines.line(to: NSPoint(x: bounds.width - 10, y: headerY))
        if isExpanded && detailRow != nil {
            lines.move(to: NSPoint(x: 12, y: headerY + 219)); lines.line(to: NSPoint(x: bounds.width - 12, y: headerY + 219))
        }
        lines.stroke()
    }
}
