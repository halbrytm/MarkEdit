// Testuje prawdziwy MarkdownDocument na plikach tymczasowych, bez okna WebKit.
// swiftc Sources/MarkEdit/MarkdownDocument.swift tests/documenttest/main.swift -o /tmp/documenttest
import AppKit

final class EditorWindowController: NSWindowController {
    var reloadID: String?
    convenience init(document: MarkdownDocument) { self.init(window: nil) }
    func pushText(_ text: String) {}
    func hideBanner() {}
    func refreshStatus() {}
    func showMissing() {}
    func showConflict(disk: String) {}
    func toast(_ message: String) {}
    func requestDiskReload(_ text: String, expected: String, id: String) { reloadID = id }
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: dir) }
let url = dir.appendingPathComponent("document.md")
func write(_ text: String, at timestamp: TimeInterval) throws {
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: timestamp)], ofItemAtPath: url.path)
}
func check(_ condition: Bool, _ message: String) {
    guard condition else { print("FAIL: \(message)"); exit(1) }
    print("ok: \(message)")
}
let type = "net.daringfireball.markdown"
try write("original", at: 1000)
let doc = MarkdownDocument()
doc.fileURL = url
doc.fileType = type
try doc.read(from: Data("original".utf8), ofType: type)
doc.checkDisk()
doc.editorDidChange("local")
try write("external B", at: 2000)
doc.checkDisk()
check(doc.conflictDiskText == "external B", "wykrycie konfliktu")
try write("\u{FEFF}external C\r\n", at: 3000)
doc.resolveConflict(keepMine: false)
check(doc.text == "external C\n", "rozwiązanie wczytuje najnowszą treść")
check(try doc.data(ofType: type) == Data("\u{FEFF}external C\r\n".utf8), "zachowanie aktualnego BOM i CRLF")
doc.checkDisk()
check(!doc.isDocumentEdited && doc.conflictDiskText == nil, "wczytana wersja jest zapisana")
try write("external D", at: 4000)
doc.checkDisk()
check(doc.text == "external D", "kolejna zmiana nadal wykrywana")

let editor = EditorWindowController(document: doc)
doc.addWindowController(editor)
try write("external E", at: 5000)
doc.checkDisk()
check(doc.text == "external D", "oczekiwanie na potwierdzenie edytora")
let rejectedID = editor.reloadID!
doc.finishDiskReload(id: rejectedID, applied: false, currentText: "local pending")
check(doc.text == "local pending" && doc.isDocumentEdited, "odrzucone przeładowanie zachowuje edycję")
check(doc.conflictDiskText == "external E", "odrzucone przeładowanie tworzy konflikt")
doc.resolveConflict(keepMine: false)
try write("external F", at: 6000)
doc.checkDisk()
doc.finishDiskReload(id: rejectedID, applied: true, currentText: "external E")
check(doc.text == "external E", "stara odpowiedź nie zmienia dokumentu")
doc.finishDiskReload(id: editor.reloadID!, applied: true, currentText: "external F")
check(doc.text == "external F" && !doc.isDocumentEdited, "potwierdzone przeładowanie")
print("ALL PASSED")
