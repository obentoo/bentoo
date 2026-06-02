// LibreOffice version probe for the bentoolkit autoupdate "script" parser.
// Runs in a headless browser on https://download.documentfoundation.org/libreoffice/src/
//
// The src/ index lists 3-segment release dirs (e.g. "26.2.4/"); the actual
// release version is the 4-segment tarball inside the newest dir
// (e.g. "libreoffice-26.2.4.1.tar.xz"). Steps:
//   1) collect 3-segment dir names, pick the highest (numeric-aware sort);
//   2) fetch that dir and extract the 4-segment version from the canonical
//      "libreoffice-X.Y.Z.W.tar.xz" tarball (NOT the -dictionaries/-help/...
//      variants — the regex anchors on "libreoffice-" + digit).
// Returns the version string (already Gentoo-shaped), or "" if not found.
(async () => {
  const dirs = [...document.querySelectorAll('a')]
    .map(a => (a.getAttribute('href') || '').replace(/\/$/, ''))
    .filter(t => /^\d+\.\d+\.\d+$/.test(t))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  if (!dirs.length) return '';
  const newest = dirs[dirs.length - 1];
  const res = await fetch(location.href + newest + '/');
  if (!res.ok) return '';
  const html = await res.text();
  const m = html.match(/libreoffice-(\d+\.\d+\.\d+\.\d+)\.tar\.xz/);
  return m ? m[1] : '';
})()
