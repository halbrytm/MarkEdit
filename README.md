# MarkEdit

Natywny edytor Markdown na macOS do pracy z plikami agentów AI (CLAUDE.md, plany, SKILL.md…).

## Funkcje

- **Trzy widoki**: tylko surowy (⌘1), podzielony (⌘2), tylko podgląd (⌘3). Przełącznik jest też na pasku narzędzi.
- **Edycja w obu panelach** z natychmiastową synchronizacją. Edycja podglądu zmienia w źródle tylko linie edytowanego bloku.
- **Pasek formatowania** (Widok → Pasek formatowania, bez skrótu) z pogrubieniem, kursywą, przekreśleniem, kodem w linii, nagłówkami (rozwijana lista), cytatem, blokiem kodu, listami (punktowana/numerowana/zadania), wcięciami, linkiem, obrazem, tabelą i linią poziomą. Każdy przycisk działa i w surowym tekście, i w podglądzie — Link/Obraz/Tabela/Linia pozioma zawsze wstawiają się do źródła i przełączają na widok z surowym tekstem, żeby od razu wpisać adres czy zawartość komórek.
- **Auto-domykanie znaków formatujących** w surowym tekście: `*`, `_`, `~`, `"`, `'` (obok już istniejących nawiasów i backticka) domykają się same, z kursorem między nimi; drugie naciśnięcie `*`/`_`/`~` zaraz potem „rozrasta” parę do podwójnej (kursywa → pogrubienie/przekreślenie). Nie paruje w środku słów (np. `snake_case_name`) ani w kodzie/wzorach LaTeX, gdzie te znaki są dosłowne. Zaznaczenie tekstu + znak owija zaznaczenie.
- **Synchroniczne przewijanie** (⌥⌘Y włącza/wyłącza). Dzielnik paneli można przeciągać, dwuklik przywraca 50/50.
- **Autozapis co 30 s** oraz zapis przy zamykaniu okna. Status zapisu i liczba słów są w podtytule okna.
- **Zmiany z dysku** (np. od agenta) są sprawdzane co sekundę. Bez lokalnych zmian plik przeładowuje się po cichu. Z lokalnymi zmianami pojawia się pasek konfliktu (Pokaż różnice / Wczytaj z dysku / Zachowaj moją wersję), a autozapis zostaje wstrzymany.
- GFM (tabele, listy zadań z klikalnymi checkboxami, przekreślenia), kolorowanie kodu, Mermaid, KaTeX (`$…$`, `$$…$$`) i frontmatter YAML.
- ⌘F szuka w panelu, w którym pracujesz. ⌘+klik otwiera link (pliki `.md` otwierają się w MarkEdit).
- ⇧⌘R pokazuje plik w Finderze, ⌥⌘C kopiuje jego ścieżkę (do wklejenia agentowi).
- Karty okien macOS, jasny i ciemny motyw zgodnie z systemem, powiększanie ⌘+ / ⌘−.

Bloki Mermaid, wzory blokowe, frontmatter i surowy HTML edytuje się w lewym panelu. W podglądzie są tylko do odczytu.

## Budowanie

Wymaga tylko Command Line Tools (Swift). Pełny Xcode nie jest potrzebny.

```sh
./build.sh            # → build/MarkEdit.app
./build.sh --install  # dodatkowo kopiuje do /Applications
```

Z terminala: `open -a MarkEdit plik.md`

## Struktura

- `Sources/MarkEdit/`: powłoka w Swift (NSDocument, okno z WKWebView, menu, autozapis, obserwacja pliku)
- `Resources/web/`: edytor (`app.js`, `app.css`) i biblioteki w `vendor/` (pobiera je `scripts/fetch-vendor.sh`)
- `scripts/make_icon.swift`: generator ikony
- `tests/`: testy edytora na silniku WebKit:
  `swiftc -O tests/webtest.swift -o build/webtest && build/webtest Resources/web tests/webtest.js Resources/web/demo.md /tmp`
