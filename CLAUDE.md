# MarkEdit — kontekst dla Claude

Natywny edytor Markdown na macOS do pracy z plikami agentów AI (CLAUDE.md, plany, SKILL.md…).
Splitscreen: surowy tekst | wyrenderowany podgląd, edycja i przewijanie zsynchronizowane w obie
strony, autozapis, wykrywanie zmian z dysku (np. od agenta) z rozwiązywaniem konfliktów.

Repo: https://github.com/halbrytm/MarkEdit (publiczne). Użytkownik: `halbrytm` na GitHubie,
maszyna ma tylko Command Line Tools — **nie zakładaj Xcode**, wszystko buduje się samym Swiftem.

## Architektura — dwie warstwy

**Powłoka natywna jest celowo cienka.** Cała logika edytora (parsowanie, renderowanie, synchronizacja,
auto-domykanie, toolbar) żyje w JS i działa w zwykłym WKWebView. Swift odpowiada tylko za: okno/menu/
dokument NSDocument, plik na dysku (odczyt/zapis/autozapis/obserwacja zmian), i most JS↔Swift.

```
Sources/MarkEdit/           powłoka Swift/AppKit
  main.swift                 start aplikacji
  AppDelegate.swift           menu, otwieranie plików o nieznanych rozszerzeniach jako Markdown
  MainMenu.swift              cała definicja paska menu (budowana ręcznie, bez .xib)
  MarkdownDocument.swift       NSDocument: kodowanie (CRLF/BOM), autozapis co 30s, poll dysku co 1s,
                               konflikt/plik-usunięty — zobacz sekcję niżej
  EditorWindowController.swift okno z WKWebView, most JS↔Swift (WKScriptMessageHandler),
                               pasek narzędzi (tylko przełącznik widoku), menu→JS (evaluate)
  LocalSchemeHandler.swift    serwuje Resources/web pod markedit://app/, obrazki pod markedit://doc/

Resources/web/               CAŁY edytor — to tu jest prawdziwa logika
  index.html                  szkielet DOM (banner, formatbar, main/raw+preview, findbar, diff-modal)
  app.css                     jeden plik, zmienne CSS dla jasnego/ciemnego motywu (patrz --root tokens)
  app.js                      ~1700 linii, jeden IIFE — patrz mapa sekcji niżej
  vendor/                     CodeMirror 5, markdown-it, highlight.js, KaTeX, Mermaid, Turndown —
                               W .gitignore, pobierane przez scripts/fetch-vendor.sh (auto z build.sh)
  demo.md                     plik używany przez testy i przez tryb "otwórz w zwykłej przeglądarce"

scripts/
  fetch-vendor.sh              pobiera vendor/ (jednorazowo, potem offline)
  make_icon.swift + make-icon.sh  generują build/AppIcon.icns programistycznie (CoreGraphics, bez Sketch/Figma)

tests/
  webtest.swift                 harness: ładuje Resources/web w PRAWDZIWYM WKWebView (nie JSDOM!)
  webtest.js                    scenariusze — patrz sekcja "Testowanie" niżej

build.sh                       jedyny sposób budowania: fetchuje vendor+ikonę jeśli brak, `swift build
                                -c release`, składa .app, podpisuje ad-hoc. `--install` kopiuje do /Applications.
```

## Jak zbudować / uruchomić

```sh
./build.sh              # → build/MarkEdit.app
./build.sh --install    # + kopiuje do /Applications, restartuje jeśli działa
open -a MarkEdit plik.md
```

Nie ma projektu Xcode — to celowe (`Package.swift`, zwykły `swift build`). Jeśli kiedyś trzeba
debugować w Xcode: `xed .` otworzy paczkę Swift, ale i tak wystarczy CLI.

## Testowanie — dlaczego WKWebView, nie jsdom

`tests/webtest.swift` ładuje `Resources/web/index.html` w prawdziwym `WKWebView` (ten sam silnik
co produkcyjna aplikacja) i wykonuje `tests/webtest.js`. To ważne, bo duża część logiki (markdown-it,
Turndown, execCommand w contenteditable, CodeMirror keymapy, KaTeX/Mermaid, CSS Custom Highlight API)
zachowuje się inaczej albo w ogóle nie działa w jsdom/node — testy w prawdziwym WebKit wyłapują rzeczy,
których żaden mock nie wyłapie.

```sh
swiftc -O tests/webtest.swift -o build/webtest
build/webtest Resources/web tests/webtest.js Resources/web/demo.md /tmp/snaps
```

Wypisuje `[nazwaTestu] ok/FAIL ...` dla każdego klucza w `window.tests`, `JS errors: ...` (błędy
JS/CSP złapane w stronie) i `ALL PASSED` / `N FAILED` na końcu. Testy zaczynające się od `snap`
zapisują PNG do katalogu podanego jako 4. argument (przydatne do wizualnej kontroli po większych
zmianach UI — Read ten plik, nie zgaduj jak coś wygląda).

**Sztuczki testowe, które zaoszczędzą Ci czasu (poznane boleśnie w tej sesji — jedna z nich, „wywołaj
handler bezpośrednio”, w pierwszej wersji faktycznie UKRYŁA prawdziwego buga, patrz niżej):**
- **Nie symuluj prawdziwych klawiszy przez `KeyboardEvent` + `document.execCommand('insertText')`** —
  to NIE odwzorowuje wiernie natywnego `preventDefault`, więc dostajesz podwójne wstawienie znaku.
- **Nie testuj auto-domykania `* _ ~` wywołując handler bezpośrednio jako funkcję** — mechanizm żyje
  w `cm.on('beforeChange', ...)` właśnie DLATEGO, że wiązanie na pojedynczy znak w `extraKeys` (co
  było pierwszą wersją) okazało się niemiarodajne przy szybkim wpisywaniu, a bezpośrednie wywołanie
  funkcji całkowicie omija ten problem, dając fałszywie zielone testy. Testuj przez
  `cm.replaceSelection(ch)` BEZ podawania origin (domyślnie `'+input'`, jak prawdziwe wpisywanie) —
  to faktycznie przechodzi przez `beforeChange`, więc wyłapie regresję, gdyby ktoś kiedyś cofnął to
  z powrotem na `extraKeys`.
- Wbudowany dodatek `closebrackets` (nawiasy, cudzysłowy, backtick — te NIE mają stanu jak `* _ ~`,
  więc mogą zostać na character-keymap bez ryzyka) trzyma SWÓJ keymap w `cm.state.keyMaps[0]`, nie
  w `cm.options.extraKeys` — stąd `km["'\"'"](cm)` do testowania cudzysłowu (to wywołanie bezpośrednie
  jest tu OK, bo testujemy kod, który i tak nie ma problemu z niemiarodajnym keypress).
- Do testowania przycisków paska formatowania: **dispatchuj prawdziwy `click()`** na
  `document.querySelector('[data-cmd="bold"]')` (to działa dobrze, w przeciwieństwie do klawiszy —
  `click` nie ma konkurencyjnej natywnej akcji do podrobienia). Funkcje typu `runToolbarCommand` żyją
  w domknięciu IIFE i nie są eksportowane — nie da się ich wywołać wprost.
- Żeby sprawdzić realne tokeny/stan CodeMirrora (np. „czy jestem w bloku kodu”), nie zgaduj —
  odpytaj `cm.getTokenAt(pos).state.inner.overlay` (`.code` = kod w linii, `.codeBlock` = blok kodu;
  potwierdzone empirycznie, nie z dokumentacji, bo tryb `gfm` ma nieoczywistą, opakowaną strukturę
  stanu przez `yaml-frontmatter`).
- `grep`/`head` na `app.js` i `webtest.js` bez `-a` cichnie (pliki mają polskie znaki, część narzędzi
  klasyfikuje je jako "data"). Używaj `grep -a`.

Przy każdej zmianie w `app.js` uruchom cały `tests/webtest.js` (45 testów) — pokrywa: render wstępny
(frontmatter/GFM/math/mermaid/hljs), edycję w obu panelach z zachowaniem składni, przewijanie
synchroniczne, konflikt/przeładowanie z dysku, cały toolbar (obie ścieżki: raw i preview) i cały
mechanizm auto-domykania (sekwencja bold/italic, granica słowa, wykluczenie w kodzie/wzorach,
zaznaczenie, backspace).

## Kluczowe mechanizmy (nieoczywiste z samego czytania kodu)

**Synchronizacja podgląd ↔ źródło jest blokowa, nie znakowa.** `buildBlocks()` dzieli markdown na
bloki najwyższego poziomu (akapit, lista, tabela…), każdy zna swój zakres linii źródła. `renderPreview()`
robi diff starych/nowych bloków po kluczu (treść źródła danego bloku) — niezmienione bloki zostają w
DOM (bez migotania, kursor przeżywa). Edycja podglądu (`syncFromPreview` → `computeSegments` →
`toMarkdown` przez Turndown) zamienia na markdown TYLKO zmienione segmenty i podmienia w źródle
wyłącznie ich zakres linii — reszta pliku bajt w bajt bez zmian. To jest serce całej apki; jeśli
coś się psuje przy edycji, zacznij tutaj (`app.js:497-838`).

**Auto-domykanie `* _ ~`** (`app.js:359-496`) przechwytuje wpisanie znaku na poziomie **`beforeChange`**,
nie przez wiązanie na pojedynczy znak w `extraKeys` (`"'*'"`) — TO BYŁ BUG znaleziony przez użytkownika:
takie wiązanie opiera się na zdarzeniu `keypress`, które przy szybkim, kolejnym wpisywaniu tego samego
znaku bywa niemiarodajne (drugie naciśnięcie potrafi nie trafić w handler i przejść jako zwykłe,
dosłowne wstawienie — patrz commit „Napraw niemiarodajne auto-domykanie…”). `beforeChange` odpala się
na faktyczny efekt wpisania niezależnie od ścieżki klawiatury, więc jest tak samo pewne jak wbudowany
`closebrackets` dla nawiasów. **Jeśli kiedyś zajdzie pokusa przepisania tego z powrotem na `extraKeys`
character-binding (wygląda prościej) — nie rób tego, to dokładnie ten sam bug.**

Mechanizm ma stan (`pendingExpand`) bo lokalny kontekst (znak przed/po kursorze) NIE wystarcza do
odróżnienia „świeża para, urośnij do podwójnej” od „koniec istniejącej podwójnej pary, przeskocz” —
oba wyglądają identycznie jako `X|X`. `pendingExpand` jest kasowany przy KAŻDEJ innej zmianie dokumentu
(nie przez `cursorActivity`, które odpala się asynchronicznie i nie chroni przed tym samym problemem
czasowania). Testy dla tego mechanizmu używają `cm.replaceSelection(ch)` BEZ podawania origin (domyślnie
`'+input'`, jak prawdziwe wpisywanie) — **nigdy nie testuj tego wywołując handler bezpośrednio jako
funkcję**, to nie przechodzi przez `beforeChange` i da fałszywe zielone testy (dokładnie tak umknął
oryginalny bug).

**Pojedynczy Enter w akapicie nie tworzy widocznego złamania linii w podglądzie — to jest celowe,
zgodne ze standardem CommonMark** (miękkie złamanie = spacja; twarde wymaga dwóch spacji na końcu linii
albo `\`). Użytkownik świadomie wybrał zostawić to zgodnie ze standardem (zamiast włączać opcję
markdown-it `breaks: true`, która zmieniłaby to globalnie, ale też „pociachałaby” w podglądzie akapity
ręcznie łamane na stałej szerokości). Nie „naprawiaj” tego bez pytania, jeśli temat wróci.

**Przewijanie synchroniczne** (`app.js:958-1030`) interpoluje między „kotwicami” (linia źródła ↔
pozycja Y w podglądzie) budowanymi z `data-src-line`/`data-rel` na elementach DOM, nie prostym
procentem wysokości — bo bloki mają różne wysokości renderowane vs w tekście (np. duży wzór $$).

**MarkdownDocument.swift**: dwa niezależne timery — poll dysku co 1s (`checkDisk`) i autozapis co 30s
(`autosaveTick`, sam też wywołuje `checkDisk` najpierw). Jeśli plik zmienił się na dysku I mamy lokalne
zmiany → `conflictDiskText` ustawiony, autozapis WSTRZYMANY dopóki user nie rozwiąże (bank z przyciskami
w JS, `app.showConflict`). Jeśli zmienił się a NIE mamy lokalnych zmian → prośba `app.reloadFromDisk` o przeładowanie.
JS najpierw synchronizuje oczekujące zmiany podglądu i porównuje treść z oczekiwaną wersją Swift.
Komunikat `diskReload` potwierdza przyjęcie wersji lub tworzy konflikt; autozapis czeka na odpowiedź.
„Wczytaj z dysku” ponownie czyta plik, nie korzysta z kopii zapamiętanej w bannerze.
Testy natywnej obsługi plików: `tests/documenttest/main.swift` (instrukcja uruchomienia w README).

**Toolbar** (`app.js:1078-1412`) ma dwie ścieżki na komendę: `rawCommand`/`previewCommand`, wybierane
przez `activePane` (aktualizowany na focus cm/preview, NIE to samo co `driver` używany do scrollsync).
Link/Obraz/Tabela/Linia pozioma zawsze idą przez raw (potrzebują wpisywalnego tekstu — adres, komórki),
`insertViaRaw` przełącza widok z powrotem na split jeśli byłeś w samym podglądzie.

## Konwencje

- Cały UI, komentarze w kodzie i commit messages po polsku (użytkownik jest Polakiem, tak wolał).
- `Resources/web/vendor/` w `.gitignore` — nie commituj bibliotek, `build.sh` je fetchuje.
- Brak projektu Xcode, brak SwiftLint/SwiftFormat — kod ręcznie utrzymany w spójnym stylu z resztą pliku.
- Ikona generowana programistycznie (`scripts/make_icon.swift`, CoreGraphics) — jeśli user chce ją
  zmienić, albo edytuj ten plik, albo poproś o nowy plik PNG i podmień w `build/AppIcon.icns`.

## Znane ograniczenia (świadome uproszczenia, nie bugi)

- Diagramy Mermaid, wzory blokowe `$$…$$`, frontmatter YAML i surowy HTML w podglądzie są
  `contenteditable="false"` (`.ro-block`) — edytowalne tylko po lewej. Robienie ich edytowalnych
  w podglądzie wymagałoby renderowania z powrotem do źródłowej składni przy każdej zmianie, co nie
  ma dobrego ogólnego rozwiązania dla Mermaid/LaTeX.
- Auto-domykanie `* _ ~` nie działa przy wielu kursorach naraz (CodeMirror multi-select) — wstawia
  znak dosłownie w każdym miejscu. Rzadko używana kombinacja w tym kontekście.
- Edycja akapitu w podglądzie łączy jego ręczne złamania linii (soft wraps) w źródle w jedną linię —
  dotyczy tylko edytowanego akapitu.
- Nowy, niezapisany dokument (brak `fileURL`) nie ma autozapisu dopóki user nie zrobi pierwszego ⌘S
  (nie ma gdzie zapisać).

## Stan projektu

Wersja 1.0, w pełni działająca, opublikowana. Użytkownik na razie zadowolony z bieżącego zakresu
(splitscreen, sync scroll, autozapis, konflikty, toolbar, auto-domykanie) — brak zgłoszonych next
steps na dziś. Jeśli wracasz do tego repo: `git pull`, `./build.sh --install`, przeczytaj sekcję
"Kluczowe mechanizmy" wyżej zanim zaczniesz grzebać w `app.js`.
