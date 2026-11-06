import Cocoa

private final class CangjieLookupPanel: NSPanel {
    override func sendEvent(_ event: NSEvent) {
        // 明確點選查碼窗時接收鍵盤；其他視窗消失時仍不自動接任。
        if event.type == .leftMouseDown { makeKey() }
        super.sendEvent(event)
    }

    // 未被輸入法或刪除確認層處理的 Esc，維持原查碼視窗不關閉的行為。
    override func cancelOperation(_ sender: Any?) {}
}

final class CangjieLookupWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: CangjieLookupWindowController?
    static var isKeyWindow: Bool { shared?.window?.isKeyWindow == true }

    private enum Preference {
        static let frame = "CangjieLookupCompactFrame"
        static let width = "CangjieLookupCompactWidth"
        static let extraHeight = "CangjieLookupCompactExtraHeight"
        static let manualTopLeft = "CangjieLookupManualTopLeft"
        static let legacyFrame = "CangjieLookupWindowFrame"
        static let pinned = "CangjieLookupWindowPinned"
        static let expanded = "CangjieLookupSavedExpanded"
    }

    let lookupView: CangjieLookupContentView
    private let defaults: UserDefaults
    private let dictionaryLoader: () throws -> CangjieDictionary
    private let storeLoader: () throws -> CangjieSavedListStore
    private let localize: (String) -> String
    private let visibleFrames: () -> [NSRect]
    private let recoveryHelpURL: URL?
    private let openHelp: (URL) -> Bool
    private var dictionary: CangjieDictionary?
    private var store: CangjieSavedListStore?
    private var extraHeight: CGFloat = 0
    private var manualWidth: CGFloat = 244
    private var changingFrame = false
    private var manualTopLeft = NSPoint.zero
    private var lastProgrammaticFrame: NSRect?

    static func show() {
        // 等選單收起，避免與系統的選單焦點恢復競爭。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let controller = shared ?? CangjieLookupWindowController()
            shared = controller
            controller.fitWindow()
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            controller.window?.makeFirstResponder(controller.lookupView.input)
        }
    }

    init(defaults: UserDefaults = .standard,
         dictionaryLoader: @escaping () throws -> CangjieDictionary = { try CangjieDictionary.load() },
         storeLoader: @escaping () throws -> CangjieSavedListStore = { try CangjieSavedListStore() },
         visibleFrames: @escaping () -> [NSRect] = { NSScreen.screens.map(\.visibleFrame) },
         recoveryHelpURL: URL? = Bundle.main.url(forResource: "CangjieRecovery", withExtension: "html"),
         openHelp: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
         localize: @escaping (String) -> String = { NSLocalizedString($0, comment: "") }) {
        self.defaults = defaults
        self.dictionaryLoader = dictionaryLoader
        self.storeLoader = storeLoader
        self.localize = localize
        self.visibleFrames = visibleFrames
        self.recoveryHelpURL = recoveryHelpURL
        self.openHelp = openHelp
        lookupView = CangjieLookupContentView(localize: localize)
        let window = CangjieLookupPanel(contentRect: NSRect(x: 0, y: 0, width: 244, height: 138),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        window.hidesOnDeactivate = false
        // 輸入面板隱藏或關閉時，不自動接手焦點而被帶到其他 App 前面。
        window.becomesKeyOnlyIfNeeded = true
        window.title = localize("lookup.title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        super.init(window: window)
        window.contentView = lookupView
        window.minSize = NSSize(width: 244, height: 138)
        let savedWidth = defaults.double(forKey: Preference.width)
        let width: CGFloat = savedWidth.isFinite && savedWidth >= 244 ? savedWidth : 244
        manualWidth = width
        let savedExtra = defaults.double(forKey: Preference.extraHeight)
        extraHeight = savedExtra.isFinite ? max(0, savedExtra) : 0
        window.setFrame(NSRect(x: 0, y: 0, width: width, height: 138 + extraHeight), display: false)
        if let encoded = defaults.string(forKey: Preference.frame) ?? defaults.string(forKey: Preference.legacyFrame) {
            let prior = NSRectFromString(encoded)
            if prior.minX.isFinite && prior.maxY.isFinite {
                window.setFrameTopLeftPoint(NSPoint(x: prior.minX, y: prior.maxY))
            } else { window.center() }
        } else { window.center() }
        manualTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        if let encoded = defaults.string(forKey: Preference.manualTopLeft) {
            let point = NSPointFromString(encoded)
            if point.x.isFinite && point.y.isFinite { manualTopLeft = point }
        }
        lookupView.preferredHeightDidChange = { [weak self] _ in self?.fitWindow() }
        lookupView.pinnedDidChange = { [weak self] pinned in
            self?.defaults.set(pinned, forKey: Preference.pinned)
            self?.setPinned(pinned)
        }
        lookupView.expandedDidChange = { [weak self] expanded in
            self?.defaults.set(expanded, forKey: Preference.expanded)
        }
        lookupView.retry = { [weak self] in self?.loadResources() }
        lookupView.recoveryHelp = { [weak self] in self?.showRecoveryHelp() }
        setPinned(defaults.bool(forKey: Preference.pinned))
        lookupView.setExpanded(defaults.bool(forKey: Preference.expanded))
        loadResources()
        fitWindow()
        window.delegate = self
        window.initialFirstResponder = lookupView.input
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    private func showRecoveryHelp() {
        guard let recoveryHelpURL else {
            CangjieDiagnostics.record(operation: .recoveryHelp, result: .failure, reason: .helpResourceMissing)
            lookupView.showRecoveryHelpFailure()
            return
        }
        guard openHelp(recoveryHelpURL) else {
            CangjieDiagnostics.record(operation: .recoveryHelp, result: .failure, reason: .helpOpenFailed)
            lookupView.showRecoveryHelpFailure()
            return
        }
        CangjieDiagnostics.record(operation: .recoveryHelp, result: .success)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) { fitWindow() }

    private func loadResources() {
        var resourceIssue: String?
        var storeIssue: String?
        if dictionary == nil {
            do { dictionary = try dictionaryLoader() }
            catch { resourceIssue = localize("lookup.dictionary_error") }
        }
        if store == nil {
            do { store = try storeLoader() }
            catch { storeIssue = localize("lookup.load_error") }
        }
        lookupView.setResources(dictionary: dictionary, store: store, resourceIssue: resourceIssue, storeIssue: storeIssue)
    }

    private func setPinned(_ pinned: Bool) {
        lookupView.setPinned(pinned)
        window?.level = pinned ? .floating : .normal
        window?.collectionBehavior = pinned ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }

    private func fitWindow() {
        guard let window, !changingFrame, !window.inLiveResize else { return }
        changingFrame = true
        defer { changingFrame = false }
        let minimum = lookupView.preferredHeight
        window.minSize = NSSize(width: 244, height: minimum)
        var frame = window.frame
        frame.size.width = manualWidth
        frame.size.height = minimum + extraHeight
        frame.origin = NSPoint(x: manualTopLeft.x, y: manualTopLeft.y - frame.height)
        if let visible = visibleFrames().max(by: { intersectionArea(frame, $0) < intersectionArea(frame, $1) }) {
            frame.size.width = min(frame.width, visible.width)
            frame.size.height = min(frame.height, visible.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        lastProgrammaticFrame = frame
        window.setFrame(frame, display: false)
        lastProgrammaticFrame = window.frame
        lookupView.needsLayout = true
        lookupView.layoutSubtreeIfNeeded()
        rememberFrame()
    }

    private func intersectionArea(_ left: NSRect, _ right: NSRect) -> CGFloat {
        let intersection = left.intersection(right)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    private func rememberFrame() {
        guard let frame = window?.frame else { return }
        defaults.set(NSStringFromRect(frame), forKey: Preference.frame)
        defaults.set(manualWidth, forKey: Preference.width)
        defaults.set(extraHeight, forKey: Preference.extraHeight)
        defaults.set(NSStringFromPoint(manualTopLeft), forKey: Preference.manualTopLeft)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window, !changingFrame, window.frame != lastProgrammaticFrame else { return }
        rememberManualPosition(window.frame)
    }

    private func rememberManualPosition(_ frame: NSRect) {
        manualTopLeft = NSPoint(x: frame.minX, y: frame.maxY)
        lastProgrammaticFrame = nil
        rememberFrame()
    }

    func windowDidResize(_ notification: Notification) {
        guard let window, !changingFrame, window.frame != lastProgrammaticFrame else { return }
        // 手動縮放時先完成列換行與額外高度計算，避免 layout 回呼中途又改視窗框。
        changingFrame = true
        defer { changingFrame = false }
        lookupView.needsLayout = true
        lookupView.layoutSubtreeIfNeeded()
        manualWidth = window.frame.width
        extraHeight = max(0, window.frame.height - lookupView.preferredHeight)
        rememberManualPosition(window.frame)
    }

    func windowDidEndLiveResize(_ notification: Notification) { fitWindow() }

    func windowWillClose(_ notification: Notification) {
        lookupView.cancelDeletion()
        rememberFrame()
    }
}
