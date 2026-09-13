import AppKit

/// Dokument Markdown. Tekst w pamięci jest zawsze z końcami linii LF — oryginalne CRLF/BOM są odtwarzane przy zapisie.
///
/// Zapis: własny autozapis co 30 s (tylko gdy są zmiany) + zapis przy zamykaniu okna.
/// Zmiany z dysku (np. od agenta AI): sprawdzane co 1 s. Bez lokalnych zmian → ciche przeładowanie;
/// z lokalnymi zmianami → konflikt (autozapis wstrzymany, użytkownik wybiera wersję).
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    static let autosaveInterval: TimeInterval = 30

    private(set) var text = ""
    private var diskText: String?          // treść ostatnio zapisana/wczytana z dysku
    private var knownModDate: Date?
    private var usesCRLF = false
    private var hasBOM = false

    private(set) var conflictDiskText: String?   // != nil → konflikt, autozapis wstrzymany
    private(set) var fileMissing = false
    private(set) var lastSaved: Date?

    private struct PendingReload {
        let id: UUID
        let text: String
        let mod: Date
        let crlf: Bool
        let bom: Bool
    }
    private var pendingReload: PendingReload?

    private var pollTimer: Timer?
    private var autosaveTimer: Timer?

    var editor: EditorWindowController? { windowControllers.first as? EditorWindowController }

    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        addWindowController(EditorWindowController(document: self))
        startTimers()
    }

    // MARK: Odczyt / zapis

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = Self.decode(data)
        text = decoded.text
        diskText = decoded.text
        usesCRLF = decoded.crlf
        hasBOM = decoded.bom
        conflictDiskText = nil
        pendingReload = nil
        editor?.pushText(text)      // przy „Przywróć zachowaną wersję”
        editor?.hideBanner()
    }

    override func data(ofType typeName: String) throws -> Data {
        var out = usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
        if hasBOM { out = "\u{FEFF}" + out }
        return Data(out.utf8)
    }

    static func decode(_ data: Data) -> (text: String, crlf: Bool, bom: Bool) {
        var bytes = data
        let bom = bytes.starts(with: [0xEF, 0xBB, 0xBF])
        if bom { bytes = Data(bytes.dropFirst(3)) }
        var s = String(data: bytes, encoding: .utf8)
            ?? String(data: bytes, encoding: .windowsCP1250)
            ?? String(decoding: bytes, as: UTF8.self)
        let crlf = s.contains("\r\n")
        if crlf { s = s.replacingOccurrences(of: "\r\n", with: "\n") }
        return (s, crlf, bom)
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void) {
        let snapshot = text
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil, saveOperation != .saveToOperation { self?.didWriteToDisk(snapshot) }
            completionHandler(error)
        }
    }

    private func didWriteToDisk(_ snapshot: String) {
        diskText = snapshot
        lastSaved = Date()
        fileMissing = false
        knownModDate = currentDiskModDate()
        if text != snapshot { updateChangeCount(.changeDone) }
        editor?.refreshStatus()
    }

    /// Zamknięcie okna / wyjście z aplikacji: zapisz po cichu zamiast pytać (plik ma już ścieżkę).
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
                           contextInfo: UnsafeMutableRawPointer?) {
        if isDocumentEdited, let url = fileURL, let type = fileType, pendingReload == nil, conflictDiskText == nil, !fileMissing {
            do {
                try writeSafely(to: url, ofType: type, for: .saveOperation)
                didWriteToDisk(text)
                fileModificationDate = knownModDate
                updateChangeCount(.changeCleared)
            } catch {
                NSLog("MarkEdit: zapis przy zamykaniu nie powiódł się: \(error)")
            }
        }
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }

    override func close() {
        pollTimer?.invalidate()
        autosaveTimer?.invalidate()
        super.close()
    }

    // MARK: Zmiany z edytora

    func editorDidChange(_ newText: String) {
        guard newText != text else { return }
        text = newText
        if let diskText, text == diskText {
            updateChangeCount(.changeCleared)
        } else if !isDocumentEdited {
            updateChangeCount(.changeDone)
        }
        editor?.refreshStatus()
    }

    func saveNow() {
        guard let url = fileURL, let type = fileType else { return }
        save(to: url, ofType: type, for: .saveOperation) { [weak self] error in
            if let error { self?.presentError(error) }
        }
    }

    // MARK: Autozapis i obserwacja pliku

    private func startTimers() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkDisk()
        }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: Self.autosaveInterval, repeats: true) { [weak self] _ in
            self?.autosaveTick()
        }
    }

    private func autosaveTick() {
        checkDisk()
        guard isDocumentEdited, fileURL != nil, pendingReload == nil, conflictDiskText == nil, !fileMissing else { return }
        saveNow()
    }

    private func currentDiskModDate() -> Date? {
        guard let path = fileURL?.path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    func checkDisk() {
        guard pendingReload == nil, let url = fileURL, diskText != nil else { return }
        guard let mod = currentDiskModDate() else {
            if !fileMissing {
                fileMissing = true
                editor?.showMissing()
                editor?.refreshStatus()
            }
            return
        }
        if fileMissing {
            fileMissing = false
            knownModDate = nil
            editor?.hideBanner()
        }
        if mod == knownModDate { return }
        guard let data = try? Data(contentsOf: url) else { return }
        knownModDate = mod
        let disk = Self.decode(data)
        if disk.text == diskText {
            fileModificationDate = mod
            return
        }
        if !isDocumentEdited || text == disk.text {
            // WebKit może mieć edycję, której most jeszcze nie przekazał do Swift.
            // Dopiero odpowiedź edytora pozwala przyjąć wersję z dysku.
            let reload = PendingReload(id: UUID(), text: disk.text, mod: mod, crlf: disk.crlf, bom: disk.bom)
            pendingReload = reload
            if let editor {
                editor.requestDiskReload(disk.text, expected: text, id: reload.id.uuidString)
            } else {
                finishDiskReload(id: reload.id.uuidString, applied: true, currentText: disk.text)
            }
        } else {
            conflictDiskText = disk.text
            editor?.showConflict(disk: disk.text)
            editor?.refreshStatus()
        }
    }

    func cancelDiskReload() {
        pendingReload = nil
        knownModDate = nil
    }

    func finishDiskReload(id: String, applied: Bool, currentText: String) {
        guard let reload = pendingReload, reload.id.uuidString == id else { return }
        pendingReload = nil
        if applied {
            adoptDisk(reload.text, mod: reload.mod, crlf: reload.crlf, bom: reload.bom, push: false)
            editor?.toast("Plik zmieniony na dysku — przeładowano")
        } else {
            editorDidChange(currentText)
            conflictDiskText = reload.text
            editor?.showConflict(disk: reload.text)
            editor?.refreshStatus()
        }
    }

    private func adoptDisk(_ disk: String, mod: Date?, crlf: Bool, bom: Bool, push: Bool = true) {
        text = disk
        diskText = disk
        usesCRLF = crlf
        hasBOM = bom
        fileModificationDate = mod
        knownModDate = mod
        conflictDiskText = nil
        updateChangeCount(.changeCleared)
        if push { editor?.pushText(disk) }
        editor?.hideBanner()
        editor?.refreshStatus()
    }

    func resolveConflict(keepMine: Bool) {
        guard conflictDiskText != nil, let url = fileURL else { return }
        // Data i treść muszą dotyczyć tego samego odczytu, a nie starego bannera.
        let mod = currentDiskModDate()
        let disk: (text: String, crlf: Bool, bom: Bool)
        do {
            disk = Self.decode(try Data(contentsOf: url))
        } catch {
            checkDisk()
            presentError(error)
            return
        }
        if keepMine {
            conflictDiskText = nil
            diskText = disk.text
            fileModificationDate = mod
            knownModDate = mod
            editor?.hideBanner()
            saveNow()
        } else {
            adoptDisk(disk.text, mod: mod, crlf: disk.crlf, bom: disk.bom)
        }
    }

    func resaveMissing() {
        fileMissing = false
        editor?.hideBanner()
        saveNow()
    }
}
