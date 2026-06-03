// Antigravity IDE version probe for the bentoolkit autoupdate "script" parser.
// Runs in a headless browser on https://antigravity.google/download (Angular SPA;
// raw HTML is empty, so only the script sees the rendered download links).
//
// Since the I/O 2026 split, the page offers two products: "Antigravity 2.0"
// (the new desktop hub, served from .../antigravity-hub/...) and the original
// "Antigravity IDE" (the VS Code fork this package tracks, served from the
// edgedl CDN under /antigravity/stable/<ver>-<build>/...). Match ONLY the IDE
// link so the hub's higher 2.0.x never leaks in. Return PV form "X.Y.Z.BUILD".
(() => {
  const a = [...document.querySelectorAll('a[href]')]
    .map(e => e.getAttribute('href'))
    .find(h => /\/antigravity\/stable\//.test(h) && /\.tar\.gz/.test(h));
  if (!a) return '';
  const m = a.match(/\/stable\/(\d+\.\d+\.\d+)-(\d+)\//);
  return m ? `${m[1]}.${m[2]}` : '';
})()
