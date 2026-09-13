import AppKit
import WebKit

final class EditorWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    WKNavigationDelegate, WKScriptMessageHandler {

    enum ViewMode: String, CaseIterable {
        case raw, split, preview
    }

    private static let modeItemID = NSToolbarItem.Identifier("viewMode")
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdx", "mdc", "txt"]

    private let webView: WKWebView
    private let schemeHandler: LocalSchemeHandler
    private weak var doc: MarkdownDocument?
    private var pageReady = false
    private var pendingCalls: [(String, [String: Any])] = []
    private var mode: ViewMode
    private var scrollSync: Bool
    private var formatBarVisible: Bool
    private var modeControl: NSSegmentedControl?
    private var statusWork: DispatchWorkItem?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    init(document: MarkdownDocument) {
        doc = document
        let defaults = UserDefaults.standard
        mode = ViewMode(rawValue: defaults.string(forKey: "viewMode") ?? "") ?? .split
        scrollSync = defaults.object(forKey: "scrollSync") as? Bool ?? true
        formatBarVisible = defaults.object(forKey: "formatBarVisible") as? Bool ?? true

        schemeHandler = LocalSchemeHandler(webRoot: Bundle.main.resourceURL!.appendingPathComponent("web"))
        schemeHandler.document = document

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: LocalSchemeHandler.scheme)
        let proxy = WeakScriptMessageHandler()
        config.userContentController.add(proxy, name: "bridge")
        webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 560, height: 360)
        window.toolbarStyle = .unified
        window.tabbingIdentifier = "MarkEditDocument"
        window.contentView = webView
        window.center()

        super.init(window: window)
        proxy.target = self
        window.delegate = self
        windowFrameAutosaveName = "MarkEditEditorWindow"
        shouldCascadeWindows = true

        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 13.3, *) { webView.isInspectable = true }
        let zoom = defaults.double(forKey: "zoom")
        webView.pageZoom = zoom > 0 ? zoom : 1

        let toolbar = NSToolbar(identifier: "MarkEditToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        webView.load(URLRequest(url: URL(string: "\(LocalSchemeHandler.scheme)://app/index.html")!))
        refreshStatus()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Most JS ⇄ Swift

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            pageReady = true
            evaluate("app.init(text, mode, scrollSync, formatBarVisible)",
                     ["text": doc?.text ?? "", "mode": mode.rawValue, "scrollSync": scrollSync, "formatBarVisible": formatBarVisible])
            let queued = pendingCalls
            pendingCalls.removeAll()
            queued.forEach { evaluate($0.0, $0.1) }
            if let disk = doc?.conflictDiskText { showConflict(disk: disk) }
        case "diskReload":
            if let id = body["id"] as? String, let applied = body["applied"] as? Bool,
               let text = body["text"] as? String {
                doc?.finishDiskReload(id: id, applied: applied, currentText: text)
            }
        case "change":
            if let text = body["text"] as? String { doc?.editorDidChange(text) }
        case "openLink":
            if let href = body["href"] as? String { openLink(href) }
        case "resolve":
            switch body["choice"] as? String {
            case "mine": doc?.resolveConflict(keepMine: true)
            case "disk": doc?.resolveConflict(keepMine: false)
            case "resave": doc?.resaveMissing()
            default: break
            }
        default:
            break
        }
    }

    private func evaluate(_ js: String, _ args: [String: Any] = [:]) {
        guard pageReady else {
            pendingCalls.append((js, args))
            return
        }
        webView.callAsyncJavaScript(js, arguments: args, in: nil, in: .page) { result in
            if case .failure(let error) = result { NSLog("MarkEdit JS error: \(error)") }
        }
    }

    func requestDiskReload(_ text: String, expected: String, id: String) {
        guard pageReady else {
            doc?.finishDiskReload(id: id, applied: true, currentText: text)
            return
        }
        webView.callAsyncJavaScript("app.reloadFromDisk(text, expected, id)",
            arguments: ["text": text, "expected": expected, "id": id], in: nil, in: .page) { [weak self] result in
                if case .failure = result { self?.doc?.cancelDiskReload() }
            }
    }

    func pushText(_ text: String) {
        guard pageReady else { return }   // app.init i tak wyśle aktualny tekst
        evaluate("app.load(text)", ["text": text])
    }

    func showConflict(disk: String) { evaluate("app.showConflict(disk)", ["disk": disk]) }
    func showMissing() { evaluate("app.showMissing()") }
    func hideBanner() { evaluate("app.hideBanner()") }
    func toast(_ message: String) { evaluate("app.toast(message)", ["message": message]) }

    // MARK: Status w podtytule okna

    func refreshStatus() {
        statusWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateSubtitle() }
        statusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func updateSubtitle() {
        guard let doc else { return }
        let words = doc.text.split(whereSeparator: { $0.isWhitespace }).count
        var parts = ["\(words) \(Self.plural(words, "słowo", "słowa", "słów"))"]
        if doc.fileURL == nil {
            parts.append("nowy plik — ⌘S, aby zapisać")
        } else if doc.fileMissing {
            parts.append("plik usunięty z dysku — autozapis wstrzymany")
        } else if doc.conflictDiskText != nil {
            parts.append("konflikt ze zmianą na dysku — autozapis wstrzymany")
        } else if doc.isDocumentEdited {
            parts.append("niezapisane · autozapis co \(Int(MarkdownDocument.autosaveInterval)) s")
        } else if let saved = doc.lastSaved {
            parts.append("zapisano \(Self.timeFormatter.string(from: saved))")
        } else {
            parts.append("zapisano")
        }
        window?.subtitle = parts.joined(separator: " · ")
    }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return one }
        let d = n % 10, dd = n % 100
        return (2...4).contains(d) && !(12...14).contains(dd) ? few : many
    }

    // MARK: Tryby widoku

    private func setMode(_ newMode: ViewMode) {
        mode = newMode
        modeControl?.selectedSegment = ViewMode.allCases.firstIndex(of: newMode) ?? 1
        UserDefaults.standard.set(newMode.rawValue, forKey: "viewMode")
        evaluate("app.setMode(mode)", ["mode": newMode.rawValue])
    }

    @objc func showRawOnly(_ sender: Any?) { setMode(.raw) }
    @objc func showSplit(_ sender: Any?) { setMode(.split) }
    @objc func showPreviewOnly(_ sender: Any?) { setMode(.preview) }
    @objc private func modeSegmentChanged(_ sender: NSSegmentedControl) {
        setMode(ViewMode.allCases[sender.selectedSegment])
    }

    @objc func toggleFormatBar(_ sender: Any?) {
        formatBarVisible.toggle()
        UserDefaults.standard.set(formatBarVisible, forKey: "formatBarVisible")
        evaluate("app.setFormatBarVisible(on)", ["on": formatBarVisible])
    }

    @objc func toggleScrollSync(_ sender: Any?) {
        scrollSync.toggle()
        UserDefaults.standard.set(scrollSync, forKey: "scrollSync")
        evaluate("app.setScrollSync(on)", ["on": scrollSync])
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(webView.pageZoom * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.pageZoom / 1.1) }
    @objc func resetZoom(_ sender: Any?) { setZoom(1) }
    private func setZoom(_ z: CGFloat) {
        webView.pageZoom = min(max(z, 0.5), 3)
        UserDefaults.standard.set(Double(webView.pageZoom), forKey: "zoom")
        evaluate("app.relayout()")
    }

    // MARK: Edycja (przekazywane do edytora JS)

    @objc func undoEdit(_ sender: Any?) { evaluate("app.undo()") }
    @objc func redoEdit(_ sender: Any?) { evaluate("app.redo()") }
    @objc func findInDocument(_ sender: Any?) { evaluate("app.find()") }
    @objc func findNextInDocument(_ sender: Any?) { evaluate("app.findNext(false)") }
    @objc func findPreviousInDocument(_ sender: Any?) { evaluate("app.findNext(true)") }

    @objc func revealInFinder(_ sender: Any?) {
        if let url = doc?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc func copyFilePath(_ sender: Any?) {
        guard let path = doc?.fileURL?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        toast("Skopiowano ścieżkę")
    }

    // MARK: Linki

    private func openLink(_ href: String) {
        if let url = URL(string: href), let scheme = url.scheme?.lowercased(), scheme != "file" {
            NSWorkspace.shared.open(url)
            return
        }
        var path = href
        if path.lowercased().hasPrefix("file://") { path = URL(string: href)?.path ?? String(path.dropFirst(7)) }
        if let hash = path.firstIndex(of: "#") { path = String(path[..<hash]) }
        path = path.removingPercentEncoding ?? path
        guard !path.isEmpty else { return }

        let target: URL
        if path.hasPrefix("/") {
            target = URL(fileURLWithPath: path)
        } else if path.hasPrefix("~") {
            target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        } else {
            let base = doc?.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
            target = base.appendingPathComponent(path).standardizedFileURL
        }
        openFile(target)
    }

    private func openFile(_ url: URL) {
        if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == LocalSchemeHandler.scheme && url.host == "app" {
            return decisionHandler(.allow)
        }
        decisionHandler(.cancel)
        if url.isFileURL {
            openFile(url)   // plik upuszczony na okno
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pageReady = false
        doc?.cancelDiskReload()
        webView.reload()
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        doc?.checkDisk()
    }

    // MARK: Pasek narzędzi

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.modeItemID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.modeItemID]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.modeItemID else { return nil }
        let segments: [(symbol: String, tip: String)] = [
            ("doc.plaintext", "Tylko surowy Markdown (⌘1)"),
            ("rectangle.split.2x1", "Podzielony widok (⌘2)"),
            ("doc.richtext", "Tylko podgląd (⌘3)"),
        ]
        let images = segments.map { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: $0.tip)! }
        let control = NSSegmentedControl(images: images, trackingMode: .selectOne,
                                         target: self, action: #selector(modeSegmentChanged(_:)))
        for (i, s) in segments.enumerated() { control.setToolTip(s.tip, forSegment: i) }
        control.selectedSegment = ViewMode.allCases.firstIndex(of: mode) ?? 1
        modeControl = control

        let item = NSToolbarItem(itemIdentifier: id)
        item.view = control
        item.label = "Widok"
        return item
    }
}

extension EditorWindowController: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(showRawOnly(_:)): item.state = mode == .raw ? .on : .off
        case #selector(showSplit(_:)): item.state = mode == .split ? .on : .off
        case #selector(showPreviewOnly(_:)): item.state = mode == .preview ? .on : .off
        case #selector(toggleFormatBar(_:)):
            item.state = formatBarVisible ? .on : .off
        case #selector(toggleScrollSync(_:)):
            item.state = scrollSync ? .on : .off
            return mode == .split
        case #selector(revealInFinder(_:)), #selector(copyFilePath(_:)):
            return doc?.fileURL != nil
        default: break
        }
        return true
    }
}

/// WKUserContentController trzyma handler mocno — pośrednik zapobiega cyklowi referencji.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
