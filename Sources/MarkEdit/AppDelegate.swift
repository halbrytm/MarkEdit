import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Pierwsza utworzona instancja staje się NSDocumentController.shared.
        _ = MarkEditDocumentController()
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Uruchomiono bez pliku (i bez przywróconych okien) → pokaż okno otwierania.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if NSDocumentController.shared.documents.isEmpty && NSApp.windows.allSatisfy({ !$0.isVisible }) {
                NSDocumentController.shared.openDocument(nil)
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.openDocument(nil) }
        return false
    }
}

/// Otwiera też pliki o nieznanych rozszerzeniach (np. .mdc) jako Markdown.
final class MarkEditDocumentController: NSDocumentController {
    override func typeForContents(of url: URL) throws -> String {
        if let type = try? super.typeForContents(of: url), documentClass(forType: type) != nil {
            return type
        }
        return "net.daringfireball.markdown"
    }
}
