#!/bin/zsh
# Pobiera biblioteki JS/CSS używane przez edytor do Resources/web/vendor (jednorazowo, potem działa offline).
set -euo pipefail
cd "$(dirname "$0")/.."
V=Resources/web/vendor
CDN=https://cdn.jsdelivr.net/npm
mkdir -p $V/cm/mode $V/cm/addon $V/katex/fonts

fetch() { curl -fsSL --retry 2 "$1" -o "$2"; echo "  ✓ $2"; }

CM=$CDN/codemirror@5.65.18
fetch $CM/lib/codemirror.js                      $V/cm/codemirror.js
fetch $CM/lib/codemirror.css                     $V/cm/codemirror.css
for m in markdown gfm yaml yaml-frontmatter javascript python shell css xml htmlmixed clike go rust sql; do
  fetch $CM/mode/$m/$m.js $V/cm/mode/$m.js
done
for a in mode/overlay mode/simple edit/continuelist search/search search/searchcursor dialog/dialog selection/active-line edit/closebrackets; do
  fetch $CM/addon/$a.js $V/cm/addon/${a:t}.js
done
fetch $CM/addon/dialog/dialog.css                $V/cm/addon/dialog.css

fetch $CDN/markdown-it@14.1.0/dist/markdown-it.min.js           $V/markdown-it.min.js
fetch $CDN/@highlightjs/cdn-assets@11.10.0/highlight.min.js      $V/highlight.min.js
fetch $CDN/@highlightjs/cdn-assets@11.10.0/styles/github.min.css      $V/hljs-light.css
fetch $CDN/@highlightjs/cdn-assets@11.10.0/styles/github-dark.min.css $V/hljs-dark.css
fetch $CDN/mermaid@11.4.1/dist/mermaid.min.js                    $V/mermaid.min.js
fetch $CDN/turndown@7.2.0/dist/turndown.js                       $V/turndown.js
fetch $CDN/turndown-plugin-gfm@1.0.2/dist/turndown-plugin-gfm.js $V/turndown-plugin-gfm.js

K=$CDN/katex@0.16.11/dist
fetch $K/katex.min.js  $V/katex/katex.min.js
fetch $K/katex.min.css $V/katex/katex.min.css
for f in $(grep -oE 'fonts/KaTeX_[A-Za-z0-9_-]+\.woff2' $V/katex/katex.min.css | sort -u); do
  fetch $K/$f $V/katex/$f
done
echo "Gotowe."
