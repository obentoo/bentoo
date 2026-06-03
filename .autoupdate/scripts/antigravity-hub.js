// Antigravity 2.0 (desktop hub) version probe for the bentoolkit autoupdate
// "script" parser. Runs in a headless browser on https://antigravity.google/download
// (Angular SPA; raw HTML is empty, so only the script sees the rendered links).
//
// The page offers two products since the I/O 2026 split: the original "Antigravity
// IDE" (served from the edgedl CDN under /antigravity/stable/...) and "Antigravity
// 2.0", the new standalone agent-orchestration hub this package tracks (served from
// storage.googleapis.com under .../antigravity-hub/<ver>-<build>/...). Match ONLY
// the hub link. Return PV form "X.Y.Z.BUILD" (e.g. 2.0.10.5119448496078848).
(() => {
  const a = [...document.querySelectorAll('a[href]')]
    .map(e => e.getAttribute('href'))
    .find(h => /\/antigravity-hub\//.test(h) && /\.tar\.gz/.test(h));
  if (!a) return '';
  const m = a.match(/\/antigravity-hub\/(\d+\.\d+\.\d+)-(\d+)\//);
  return m ? `${m[1]}.${m[2]}` : '';
})()
