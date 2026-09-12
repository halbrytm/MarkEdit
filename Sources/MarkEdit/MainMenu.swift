import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        // MarkEdit
        let app = NSMenu(title: "MarkEdit")
        add(app, "O programie MarkEdit", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        let services = NSMenu(title: "Usługi")
        app.addItem(withTitle: "Usługi", action: nil, keyEquivalent: "").submenu = services
        NSApp.servicesMenu = services
        app.addItem(.separator())
        add(app, "Ukryj MarkEdit", #selector(NSApplication.hide(_:)), "h")
        add(app, "Ukryj pozostałe", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, "Pokaż wszystkie", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Zakończ MarkEdit", #selector(NSApplication.terminate(_:)), "q")
        attach(main, app)

        // Plik
        let file = NSMenu(title: "Plik")
        add(file, "Nowy", #selector(NSDocumentController.newDocument(_:)), "n")
        add(file, "Otwórz…", #selector(NSDocumentController.openDocument(_:)), "o")
        let recent = NSMenu(title: "Otwórz ostatnie")
        add(recent, "Wyczyść menu", #selector(NSDocumentController.clearRecentDocuments(_:)))
        file.addItem(withTitle: "Otwórz ostatnie", action: nil, keyEquivalent: "").submenu = recent
        let setMenuName = NSSelectorFromString("_setMenuName:")
        if recent.responds(to: setMenuName) { recent.perform(setMenuName, with: "NSRecentDocumentsMenu") }
        file.addItem(.separator())
        add(file, "Zamknij", #selector(NSWindow.performClose(_:)), "w")
        add(file, "Zachowaj", #selector(NSDocument.save(_:)), "s")
        add(file, "Zachowaj jako…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        add(file, "Przywróć zachowaną wersję", #selector(NSDocument.revertToSaved(_:)))
        file.addItem(.separator())
        add(file, "Pokaż w Finderze", #selector(EditorWindowController.revealInFinder(_:)), "r", [.command, .shift])
        add(file, "Kopiuj ścieżkę pliku", #selector(EditorWindowController.copyFilePath(_:)), "c", [.command, .option])
        attach(main, file)

        // Edycja
        let edit = NSMenu(title: "Edycja")
        add(edit, "Cofnij", #selector(EditorWindowController.undoEdit(_:)), "z")
        add(edit, "Ponów", #selector(EditorWindowController.redoEdit(_:)), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Wytnij", #selector(NSText.cut(_:)), "x")
        add(edit, "Kopiuj", #selector(NSText.copy(_:)), "c")
        add(edit, "Wklej", #selector(NSText.paste(_:)), "v")
        add(edit, "Zaznacz wszystko", #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, "Znajdź…", #selector(EditorWindowController.findInDocument(_:)), "f")
        add(edit, "Znajdź następne", #selector(EditorWindowController.findNextInDocument(_:)), "g")
        add(edit, "Znajdź poprzednie", #selector(EditorWindowController.findPreviousInDocument(_:)), "g", [.command, .shift])
        attach(main, edit)

        // Widok
        let view = NSMenu(title: "Widok")
        add(view, "Tylko surowy Markdown", #selector(EditorWindowController.showRawOnly(_:)), "1")
        add(view, "Podzielony widok", #selector(EditorWindowController.showSplit(_:)), "2")
        add(view, "Tylko podgląd", #selector(EditorWindowController.showPreviewOnly(_:)), "3")
        view.addItem(.separator())
        add(view, "Pasek formatowania", #selector(EditorWindowController.toggleFormatBar(_:)))
        add(view, "Synchroniczne przewijanie", #selector(EditorWindowController.toggleScrollSync(_:)), "y", [.command, .option])
        view.addItem(.separator())
        add(view, "Powiększ", #selector(EditorWindowController.zoomIn(_:)), "+")
        add(view, "Pomniejsz", #selector(EditorWindowController.zoomOut(_:)), "-")
        add(view, "Rzeczywisty rozmiar", #selector(EditorWindowController.resetZoom(_:)), "0")
        view.addItem(.separator())
        add(view, "Pełny ekran", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        attach(main, view)

        // Okno
        let window = NSMenu(title: "Okno")
        add(window, "Minimalizuj", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(window, "Powiększ okno", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        add(window, "Przenieś wszystko na wierzch", #selector(NSApplication.arrangeInFront(_:)))
        attach(main, window)
        NSApp.windowsMenu = window

        return main
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ mods: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = mods }
        return item
    }

    private static func attach(_ main: NSMenu, _ submenu: NSMenu) {
        main.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
    }
}
