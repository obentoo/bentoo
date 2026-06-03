// LibreOffice version probe for the bentoolkit autoupdate "script" parser.
// Runs in a headless browser on https://download.documentfoundation.org/libreoffice/src/
//
// The src/ index lists 3-segment release dirs (e.g. "26.2.4/"); the actual
// release version is the 4-segment tarball inside the dir
// (e.g. "libreoffice-26.2.4.1.tar.xz"). Upstream also publishes the NEXT
// cycle's dir early holding only pre-releases (e.g. "26.8.0/" ->
// libreoffice-26.8.0.0.alpha1.tar.xz), so the highest dir is not necessarily
// the newest STABLE one. Steps:
//   1) collect 3-segment dir names, sort numeric-ascending;
//   2) walk newest-first and return the first dir that yields a stable
//      4-segment "libreoffice-X.Y.Z.W.tar.xz" (the regex anchors on
//      "libreoffice-" + 4 numeric groups, so -alpha/-beta/-rc tarballs and
//      the -dictionaries/-help/... variants are skipped automatically).
// Returns the version string (already Gentoo-shaped), or "" if not found.
(async () => {
  const dirs = [...document.querySelectorAll('a')]
    .map(a => (a.getAttribute('href') || '').replace(/\/$/, ''))
    .filter(t => /^\d+\.\d+\.\d+$/.test(t))
    .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  // Walk newest-first; cap the probe to the top dirs so an all-prerelease
  // tail can't trigger a long fetch chain.
  for (let i = dirs.length - 1; i >= 0 && i >= dirs.length - 8; i--) {
    const res = await fetch(location.href + dirs[i] + '/');
    if (!res.ok) continue;
    const html = await res.text();
    const m = html.match(/libreoffice-(\d+\.\d+\.\d+\.\d+)\.tar\.xz/);
    if (m) return m[1];
  }
  return '';
})()
