// Scenariusze testowe edytora — uruchamiane przez tests/webtest.swift w WKWebView.
const cm = document.querySelector('.CodeMirror').CodeMirror;
const preview = document.getElementById('preview');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const frame = () => new Promise((r) => requestAnimationFrame(() => r()));
const src = () => cm.getValue();
const ok = (cond, msg) => (cond ? 'ok ' + msg : 'FAIL ' + msg);
const check = (pairs) => {
  const bad = pairs.filter(([c]) => !c).map(([, m]) => m);
  return bad.length ? 'FAIL ' + bad.join('; ') : 'ok (' + pairs.length + ' checks)';
};

function caretAtEnd(el) {
  preview.focus();
  const r = document.createRange();
  r.selectNodeContents(el);
  r.collapse(false);
  const s = getSelection();
  s.removeAllRanges();
  s.addRange(r);
}
function caretAtStart(el) {
  preview.focus();
  const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  const t = w.nextNode();
  const r = document.createRange();
  r.setStart(t, 0);
  r.collapse(true);
  getSelection().removeAllRanges();
  getSelection().addRange(r);
}
async function typeInPreview(text) {
  document.execCommand('insertText', false, text);
  preview.dispatchEvent(new InputEvent('input', { bubbles: true }));
  await sleep(300);
}
const find = (sel, text) => [...preview.querySelectorAll(sel)].find((e) => e.textContent.includes(text));
const click = (cmd) => { document.querySelector(`[data-cmd="${cmd}"]`).click(); };
const setHeading = (n) => { const s = document.getElementById('fb-heading'); s.value = String(n); s.dispatchEvent(new Event('change')); };

let original;

window.tests = {
  async initialRender() {
    await sleep(1500);   // mermaid
    original = src();
    return check([
      [preview.querySelector('.frontmatter'), 'frontmatter'],
      [find('h1', 'Plan pracy agenta'), 'h1'],
      [preview.querySelectorAll('.task-cb input').length === 3, 'task checkboxes'],
      [preview.querySelector('.task-cb input').checked, 'first checked'],
      [preview.querySelector('.math-inline .katex'), 'inline math'],
      [preview.querySelector('.math-block .katex-display'), 'block math'],
      [preview.querySelector('table th'), 'table'],
      [preview.querySelector('pre code .hljs-keyword'), 'hljs'],
      [preview.querySelector('.mermaid-out svg'), 'mermaid svg: ' + (preview.querySelector('.mermaid-out') || {}).textContent],
      [!preview.textContent.includes('komentarz HTML') || preview.querySelector('.is-comment'), 'comment hidden'],
      [find('p', '$5 i $10'), 'dollar prices not math'],
    ]);
  },

  async snapSplit() { return 'snapshot'; },

  async rawToPreview() {
    const line = cm.lineCount() - 2;
    cm.replaceRange(' ZMIANA_Z_LEWEJ', { line, ch: cm.getLine(line).length });
    await frame(); await frame();
    return ok(find('p', 'Ostatni akapit. ZMIANA_Z_LEWEJ'), 'raw edit visible in preview');
  },

  async previewTypeInParagraph() {
    const before = src();
    const p = find('p', 'Ostatni akapit');
    caretAtEnd(p);
    await typeInPreview(' i_tekst z_prawej');
    const after = src();
    const changedLines = after.split('\n').filter((l, i) => l !== before.split('\n')[i]);
    return check([
      [after.includes('Ostatni akapit. ZMIANA_Z_LEWEJ i_tekst z_prawej'), 'text appended in source: ' + JSON.stringify(after.slice(-80))],
      [changedLines.length === 1, 'only one line changed: ' + JSON.stringify(changedLines)],
      [p.isConnected, 'edited element kept (caret preserved)'],
    ]);
  },

  async previewEnterNewParagraph() {
    const p = find('p', 'Ostatni akapit');
    caretAtEnd(p);
    document.execCommand('insertParagraph');
    preview.dispatchEvent(new InputEvent('input', { bubbles: true }));
    await sleep(300);
    await typeInPreview('Nowy akapit z podglądu');
    const s = src();
    return check([
      [/z_prawej\n\nNowy akapit z podglądu\n?$/.test(s), 'new paragraph in source: ' + JSON.stringify(s.slice(-70))],
      [find('p', 'Nowy akapit z podglądu'), 'still in preview'],
    ]);
  },

  async previewEditKeepsSpecialSyntax() {
    const p = find('p', 'akapit');   // pierwszy akapit z math, linkiem, snake_case
    caretAtEnd(p);
    await typeInPreview(' Koniec.');
    const s = src();
    return check([
      [s.includes('$E = mc^2$'), 'inline math kept'],
      [s.includes('snake_case_name'), 'snake_case not escaped'],
      [s.includes('[linkiem](https://example.com)'), 'link kept'],
      [s.includes('`kodem`'), 'code kept'],
      [s.includes('$5 i $10. Koniec.'), 'typed text: ' + JSON.stringify(s.split('\n').find((l) => l.includes('Koniec')))],
      [s.startsWith('---\nname: demo-agent'), 'frontmatter intact'],
    ]);
  },

  async toggleCheckbox() {
    const cb = preview.querySelectorAll('.task-cb')[1];
    cb.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
    await frame(); await frame();
    return check([
      [src().includes('- [x] Napisać testy'), 'source toggled'],
      [preview.querySelectorAll('.task-cb input')[1].checked, 'preview checked'],
    ]);
  },

  async editNestedList() {
    const li = find('li', 'Drugi krok');
    const textNode = [...li.childNodes].find((n) => n.nodeType === 3 && n.textContent.includes('Drugi'));
    preview.focus();
    const r = document.createRange();
    r.setStart(textNode, textNode.textContent.indexOf('krok') + 4);
    r.collapse(true);
    getSelection().removeAllRanges();
    getSelection().addRange(r);
    await typeInPreview(' (edytowany)');
    const s = src();
    return ok(s.includes('1. Pierwszy krok\n2. Drugi krok (edytowany)\n   - zagnieżdżony punkt\n   - kolejny'),
      'list markdown preserved: ' + JSON.stringify(s.slice(s.indexOf('1. Pierw'), s.indexOf('1. Pierw') + 90)));
  },

  async editTableCell() {
    const td = find('td', 'w toku');
    caretAtEnd(td);
    await typeInPreview('!');
    const s = src();
    return ok(/\| `main.swift` \| 🚧 \| w toku! \|/.test(s), 'table row: ' + JSON.stringify(s.split('\n').find((l) => l.includes('main.swift'))));
  },

  async undoFromApp() {
    app.undo();
    await frame(); await frame();
    return ok(src().includes('| w toku |'), 'undo reverted table edit');
  },

  async deleteParagraphInPreview() {
    const p = find('p', 'Duis aute');
    preview.focus();
    const r = document.createRange();
    r.selectNode(p);
    getSelection().removeAllRanges();
    getSelection().addRange(r);
    document.execCommand('delete');
    preview.dispatchEvent(new InputEvent('input', { bubbles: true }));
    await sleep(300);
    const s = src();
    return check([
      [!s.includes('Duis aute'), 'paragraph removed from source'],
      [s.includes('laboris nisi ut aliquip ex ea commodo consequat.\n\nOstatni'), 'neighbours joined cleanly: ' + JSON.stringify(s.slice(s.indexOf('consequat.'), s.indexOf('consequat.') + 30))],
    ]);
  },

  async headingEdit() {
    const h = find('h2', 'Zadania');
    caretAtEnd(h);
    await typeInPreview(' na dziś');
    return ok(src().includes('\n## Zadania na dziś\n'), 'heading');
  },

  async boldViaCommand() {
    const h = find('p', 'Ostatni akapit');
    caretAtEnd(h);
    document.execCommand('bold');
    await typeInPreview(' pogrubione');
    return ok(/\*\*\s?pogrubione\*\*/.test(src()), 'bold: ' + JSON.stringify(src().split('\n').find((l) => l.includes('pogrubione'))));
  },

  async reloadPreservesPendingPreviewEdit() {
    const saved = src();
    app.load('Oryginał');
    await frame(); await frame();
    caretAtEnd(preview.querySelector('p'));
    document.execCommand('insertText', false, ' lokalnie');
    preview.dispatchEvent(new InputEvent('input', { bubbles: true }));
    const applied = app.reloadFromDisk('Wersja agenta', 'Oryginał', 'test-preview');
    const result = check([
      [applied === false, 'przeładowanie odrzucone'],
      [src().includes('lokalnie'), 'niezakończona edycja zachowana'],
    ]);
    app.load(saved);
    await frame(); await frame();
    return result;
  },

  async reloadPreservesNewRawEdit() {
    const saved = src();
    app.load('Oryginał');
    cm.replaceRange(' lokalnie', { line: 0, ch: 8 });
    const applied = app.reloadFromDisk('Wersja agenta', 'Oryginał', 'test-raw');
    const result = check([
      [applied === false, 'odrzucono nieaktualny stan Swift'],
      [src().includes('lokalnie'), 'edycja źródła zachowana'],
    ]);
    app.load(saved);
    await frame(); await frame();
    return result;
  },

  async reloadAcceptsUnchangedEditor() {
    const saved = src();
    const applied = app.reloadFromDisk('Wersja agenta', saved, 'test-clean');
    const result = check([[applied === true, 'przeładowanie przyjęte'], [src() === 'Wersja agenta', 'nowa treść']]);
    app.load(saved);
    await frame(); await frame();
    return result;
  },

  async externalReload() {
    const cur = src();
    cm.setCursor({ line: 3, ch: 2 });
    app.load(cur.replace('# Plan pracy agenta', '# Plan pracy agenta (od agenta)'));
    await frame(); await frame();
    return check([
      [find('h1', '(od agenta)'), 'preview updated'],
      [cm.getCursor().line === 3, 'cursor kept'],
    ]);
  },

  async scrollSync() {
    app.setMode('split');
    await frame();
    const raw = cm.getScrollerElement();
    const pane = document.getElementById('preview-pane');
    raw.dispatchEvent(new WheelEvent('wheel', { bubbles: true }));
    const line = src().split('\n').findIndex((l) => l.startsWith('| Plik'));
    raw.scrollTop = cm.heightAtLine(line, 'local');
    await sleep(100);
    const table = preview.querySelector('table');
    const off = table.getBoundingClientRect().top - pane.getBoundingClientRect().top;
    raw.scrollTop = raw.scrollHeight;
    await sleep(100);
    const atEnd = pane.scrollTop >= pane.scrollHeight - pane.clientHeight - 2;
    raw.scrollTop = 0;
    await sleep(100);
    return check([
      [Math.abs(off) < 30, 'table aligned to top of preview (offset ' + Math.round(off) + 'px)'],
      [atEnd, 'bottom synced'],
      [pane.scrollTop === 0, 'top synced'],
    ]);
  },

  async snapRawOnly() { app.setMode('raw'); await sleep(100); return 'snapshot'; },
  async snapPreviewOnly() { app.setMode('preview'); await sleep(100); return 'snapshot'; },

  async findInPreview() {
    app.find();
    const input = document.getElementById('find-input');
    input.value = 'akapit';
    input.dispatchEvent(new Event('input'));
    input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter' }));
    const count = document.getElementById('find-count').textContent;
    return ok(/^1\/\d+$/.test(count), 'find count ' + count);
  },

  async snapConflict() {
    app.setMode('split');
    app.showConflict(src().replace('Ostatni', 'Zmienione przez agenta'));
    document.querySelector('#banner button').click();
    await sleep(100);
    return 'snapshot';
  },

  // ── Auto-domykanie * _ ~ jest przechwytywane na poziomie beforeChange (patrz komentarz w app.js
  //    nad `cm.on('beforeChange', ...)` — wiązanie na pojedynczy znak w extraKeys okazało się
  //    niemiarodajne przy szybkim, kolejnym wpisywaniu tego samego znaku). Testujemy przez
  //    `cm.replaceSelection(ch)` BEZ podawania origin — domyślnie dostaje '+input', dokładnie jak
  //    prawdziwe wpisywanie — więc idzie przez ten sam pipeline beforeChange, a nie obok niego. ──

  async pairBoldItalicSequence() {
    const type = (ch) => cm.replaceSelection(ch);
    const st = () => { const c = cm.getCursor(); return cm.getLine(c.line).slice(0, c.ch) + '|' + cm.getLine(c.line).slice(c.ch); };
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    type('*'); const s1 = st();
    type('*'); const s2 = st();
    type('T'); const s3 = st();
    type('*'); const s4 = st();
    type('*'); const s5 = st();
    return check([
      [s1 === '*|*', '1. * -> *|* (było: ' + s1 + ')'],
      [s2 === '**|**', '2. * -> **|** (było: ' + s2 + ') — dokładnie zgłoszony przez użytkownika przypadek szybkiego podwójnego wpisania *'],
      [s3 === '**T|**', 'wpisanie T -> **T|** (było: ' + s3 + ')'],
      [s4 === '**T*|*', '3. * przeskakuje -> **T*|* (było: ' + s4 + ')'],
      [s5 === '**T**|', '4. * przeskakuje -> **T**| (było: ' + s5 + ')'],
    ]);
  },

  async pairUnderscoreAndTilde() {
    const type = (ch) => cm.replaceSelection(ch);
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    ['_', '_', 't', '_', '_'].forEach(type);
    const u = cm.getValue();
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    ['~', '~', 't', '~', '~'].forEach(type);
    const t = cm.getValue();
    return check([[u === '__t__', 'podkreślenie rozrasta się tak samo jak gwiazdka: ' + u], [t === '~~t~~', 'tylda rozrasta się tak samo: ' + t]]);
  },

  async pairWordBoundary() {
    const type = (ch) => cm.replaceSelection(ch);
    cm.setValue('snake_case_name'); cm.setCursor({ line: 0, ch: 5 });
    type('_');
    const midWord = cm.getValue() === 'snake_case_name';
    cm.setValue('hello '); cm.setCursor({ line: 0, ch: 6 });
    type('*');
    const afterSpace = cm.getValue() === 'hello **';
    return check([
      [midWord, 'brak parowania w środku słowa (snake_case_name)'],
      [afterSpace, 'parowanie po spacji: ' + JSON.stringify(cm.getValue())],
    ]);
  },

  async pairSkipsCodeAndMath() {
    const at = (text, needle, offset) => {
      cm.setValue(text);
      const idx = text.indexOf(needle) + (offset || 0);
      const before = text.slice(0, idx);
      const line = before.split('\n').length - 1;
      const ch = before.length - before.lastIndexOf('\n') - 1;
      cm.setCursor({ line, ch });
      const before2 = cm.getValue();
      cm.replaceSelection('*');
      return cm.getValue() === before2.slice(0, idx) + '*' + before2.slice(idx);
    };
    return check([
      [at('`code`', 'code', 2), 'dosłowny * w kodzie w linii'],
      [at('```\na*b\n```', 'a', 1), 'dosłowny * w bloku kodu'],
      [at('$a*b$', 'a', 1), 'dosłowny * we wzorze $..$'],
      [at('$$\na*b\n$$', 'a', 1), 'dosłowny * we wzorze $$..$$'],
    ]);
  },

  async pairStaleExpandDoesNotCorrupt() {
    // * -> *|* (pendingExpand ustawiony), wpisujemy coś INNEGO w to miejsce, wracamy kursorem
    // dokładnie tam, gdzie było pendingExpand, i wpisujemy * ponownie — to NIE powinno być
    // potraktowane jako kontynuacja (bo tekst się zmienił), inaczej „rozrośnie” niepasujący fragment.
    const type = (ch) => cm.replaceSelection(ch);
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    type('*');
    cm.setCursor({ line: 0, ch: 1 });
    type('X');
    cm.setCursor({ line: 0, ch: 1 });
    type('*');
    return ok(cm.getValue() === '**X*', 'brak fałszywego rozrostu po edycji między parą: ' + JSON.stringify(cm.getValue()));
  },

  async pairSelectionWrapAndBackspace() {
    cm.setValue('hello world');
    cm.setSelection({ line: 0, ch: 0 }, { line: 0, ch: 5 });
    cm.replaceSelection('*');
    const wrapped = cm.getValue() === '*hello* world' && cm.getSelection() === 'hello';
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    cm.replaceSelection('*');
    cm.options.extraKeys.Backspace(cm);
    return check([
      [wrapped, 'zaznaczenie owinięte gwiazdkami, zaznaczenie zachowane'],
      [cm.getValue() === '', 'backspace kasuje pustą parę naraz'],
    ]);
  },

  async quotesAndBracketsStillAutoClose() {
    const km = cm.state.keyMaps[0];
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    km["'\"'"](cm);
    const dq = cm.getValue() === '""';
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    km["'''"](cm);
    const sq = cm.getValue() === "''";
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    km["'('"](cm);
    const br = cm.getValue() === '()';
    return check([[dq, 'cudzysłów podwójny nadal paruje'], [sq, 'cudzysłów pojedynczy nadal paruje'], [br, 'nawias nadal paruje']]);
  },

  // ── Pasek formatowania: każde polecenie ma ścieżkę surową i ścieżkę podglądu (patrz activePane
  //    w app.js) — klikamy prawdziwy przycisk (click()), żeby przejść przez faktyczny addEventListener,
  //    a nie wołać wewnętrzne funkcje (te nie są eksportowane poza domknięcie app.js). ──

  async rawInlineStyles() {
    cm.setValue('hello world'); cm.focus();
    cm.setSelection({ line: 0, ch: 0 }, { line: 0, ch: 5 });
    await frame();
    click('bold');
    const afterBold = cm.getValue();
    cm.setSelection({ line: 0, ch: 2 }, { line: 0, ch: 7 });
    click('italic');
    return check([
      [afterBold === '**hello** world', 'bold wraps zaznaczenie: ' + JSON.stringify(afterBold)],
      [cm.getValue().includes('*'), 'kursywa zastosowana: ' + JSON.stringify(cm.getValue())],
    ]);
  },

  async rawHeadingToggle() {
    cm.setValue('Tytul'); cm.focus(); cm.setCursor({ line: 0, ch: 2 });
    await frame();
    setHeading(2);
    const h2 = cm.getValue();
    cm.setCursor({ line: 0, ch: 2 });
    setHeading(0);
    return check([[h2 === '## Tytul', 'nagłówek 2: ' + JSON.stringify(h2)], [cm.getValue() === 'Tytul', 'usunięty: ' + JSON.stringify(cm.getValue())]]);
  },

  async rawQuoteToggle() {
    cm.setValue('linia a\nlinia b'); cm.focus();
    cm.setSelection({ line: 0, ch: 0 }, { line: 1, ch: 6 });
    await frame();
    click('quote');
    const on = cm.getValue();
    cm.setSelection({ line: 0, ch: 0 }, { line: 1, ch: 8 });
    click('quote');
    return check([[on === '> linia a\n> linia b', 'cytat wł.: ' + JSON.stringify(on)], [cm.getValue() === 'linia a\nlinia b', 'cytat wył.: ' + JSON.stringify(cm.getValue())]]);
  },

  async rawCodeBlockEmptyAndSelection() {
    cm.setValue(''); cm.focus(); cm.setCursor({ line: 0, ch: 0 });
    await frame();
    click('codeblock');
    const empty = cm.getValue();
    cm.setValue('kod tu'); cm.setSelection({ line: 0, ch: 0 }, { line: 0, ch: 6 });
    click('codeblock');
    return check([[empty === '```\n\n```', 'pusty blok: ' + JSON.stringify(empty)], [cm.getValue() === '```\nkod tu\n```', 'zaznaczenie w bloku: ' + JSON.stringify(cm.getValue())]]);
  },

  async rawListsToggle() {
    cm.setValue('a\nb'); cm.focus();
    cm.setSelection({ line: 0, ch: 0 }, { line: 1, ch: 1 });
    await frame();
    click('ul');
    const ul = cm.getValue();
    click('ol');
    const ol = cm.getValue();
    cm.setSelection({ line: 0, ch: 0 }, { line: 1, ch: 4 });
    click('task');
    const task = cm.getValue();
    click('task');
    return check([
      [ul === '- a\n- b', 'punktowana: ' + JSON.stringify(ul)],
      [ol === '1. a\n2. b', 'numerowana: ' + JSON.stringify(ol)],
      [task === '- [ ] a\n- [ ] b', 'zadania: ' + JSON.stringify(task)],
      [cm.getValue() === 'a\nb', 'zdjęcie listy: ' + JSON.stringify(cm.getValue())],
    ]);
  },

  async rawIndentOutdent() {
    cm.setValue('- a\n- b'); cm.focus(); cm.setCursor({ line: 1, ch: 3 });
    await frame();
    click('indent');
    const indented = cm.getLine(1);
    click('outdent');
    return check([[/^\s+- b/.test(indented), 'wcięcie: ' + JSON.stringify(indented)], [cm.getLine(1) === '- b', 'cofnięte wcięcie: ' + JSON.stringify(cm.getLine(1))]]);
  },

  async rawLinkImage() {
    cm.setValue('tekst'); cm.focus();
    cm.setSelection({ line: 0, ch: 0 }, { line: 0, ch: 5 });
    await frame();
    click('link');
    const withSel = cm.getValue();
    const urlSelected = cm.getSelection();
    cm.setValue(''); cm.setCursor({ line: 0, ch: 0 });
    click('image');
    return check([
      [withSel === '[tekst](url)', 'link owija zaznaczenie: ' + JSON.stringify(withSel)],
      [urlSelected === 'url', 'placeholder adresu zaznaczony: ' + JSON.stringify(urlSelected)],
      [cm.getValue() === '![opis](url)', 'placeholder obrazu: ' + JSON.stringify(cm.getValue())],
    ]);
  },

  async rawTableAndHR() {
    cm.setValue('Akapit'); cm.focus(); cm.setCursor({ line: 0, ch: 6 });
    await frame();
    click('table');
    const withTable = cm.getValue();
    cm.setValue('Akapit'); cm.setCursor({ line: 0, ch: 6 });
    click('hr');
    return check([
      [withTable === 'Akapit\n\n| Nagłówek 1 | Nagłówek 2 |\n| --- | --- |\n| Komórka | Komórka |', 'tabela: ' + JSON.stringify(withTable)],
      [cm.getValue() === 'Akapit\n\n---', 'linia pozioma: ' + JSON.stringify(cm.getValue())],
    ]);
  },

  async previewInlineStyles() {
    cm.setValue('hello world alpha'); await frame(); await frame();
    const p = find('p', 'hello world');
    preview.focus();
    const t = p.firstChild;
    const r = document.createRange(); r.setStart(t, 0); r.setEnd(t, 5);
    getSelection().removeAllRanges(); getSelection().addRange(r);
    click('bold');
    p.dispatchEvent(new InputEvent('input', { bubbles: true }));
    await sleep(300);
    return check([[!!p.querySelector('b,strong'), 'element pogrubienia w DOM'], [cm.getValue().startsWith('**hello**'), 'źródło zaktualizowane: ' + JSON.stringify(cm.getValue())]]);
  },

  async previewHeadingToggle() {
    cm.setValue('Tytul'); await frame(); await frame();
    caretAtEnd(find('p', 'Tytul'));
    setHeading(3);
    await sleep(300);
    const h3src = cm.getValue();
    const h3el = find('h3', 'Tytul');
    if (h3el) caretAtEnd(h3el);
    setHeading(0);
    await sleep(300);
    return check([
      [h3src === '### Tytul', 'nagłówek 3 z podglądu: ' + JSON.stringify(h3src)],
      [!!h3el, 'istniał element h3'],
      [cm.getValue() === 'Tytul', 'z powrotem akapit: ' + JSON.stringify(cm.getValue())],
    ]);
  },

  async previewQuoteToggle() {
    cm.setValue('Cytowany tekst'); await frame(); await frame();
    caretAtEnd(find('p', 'Cytowany'));
    click('quote');
    await sleep(300);
    return check([[cm.getValue() === '> Cytowany tekst', 'cytat z podglądu: ' + JSON.stringify(cm.getValue())], [!!find('blockquote', 'Cytowany'), 'element blockquote']]);
  },

  async previewCodeBlockToggle() {
    cm.setValue('kod tu'); await frame(); await frame();
    caretAtEnd(find('p', 'kod tu'));
    click('codeblock');
    await sleep(300);
    return ok(cm.getValue() === '```\nkod tu\n```', 'blok kodu z podglądu: ' + JSON.stringify(cm.getValue()));
  },

  async previewListsToggle() {
    cm.setValue('jeden'); await frame(); await frame();
    caretAtEnd(find('p', 'jeden'));
    click('ul');
    await sleep(300);
    const ul = cm.getValue();
    caretAtEnd(find('li', 'jeden'));
    click('task');
    await sleep(300);
    return check([[ul === '- jeden', 'punktowana z podglądu: ' + JSON.stringify(ul)], [cm.getValue() === '- [ ] jeden', 'zadanie dodane do istniejącego punktu: ' + JSON.stringify(cm.getValue())]]);
  },

  async previewLinkSwitchesToRaw() {
    cm.setValue('Akapit z tekstem'); await frame(); await frame();
    app.setMode('preview');
    caretAtEnd(find('p', 'Akapit'));
    click('link');
    await frame(); await frame();
    return check([
      [document.body.dataset.mode === 'split', 'wyjście z trybu tylko-podgląd: ' + document.body.dataset.mode],
      [cm.getValue().includes('[tekst](url)'), 'placeholder linku w źródle: ' + JSON.stringify(cm.getValue())],
    ]);
  },

  async formatBarToggle() {
    const bar = document.getElementById('formatbar');
    app.setFormatBarVisible(false);
    const hidden = bar.hidden;
    app.setFormatBarVisible(true);
    return check([[hidden, 'ukryty gdy false'], [!bar.hidden, 'widoczny gdy true']]);
  },

  async emptyDocument() {
    document.getElementById('diff-modal').hidden = true;
    app.hideBanner();
    app.load('');
    await frame(); await frame();
    preview.focus();
    const r = document.createRange();
    r.setStart(preview, 0);
    getSelection().removeAllRanges();
    getSelection().addRange(r);
    await typeInPreview('Pierwsze słowa');
    return ok(src() === 'Pierwsze słowa\n','typing into empty doc: ' + JSON.stringify(src()));
  },
};
