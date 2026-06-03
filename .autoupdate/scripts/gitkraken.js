// GitKraken Desktop version probe for the bentoolkit autoupdate "script" parser.
// Runs in a headless browser on https://support.gitkraken.com/release-notes/current
//
// www.gitkraken.com/release-notes now 301-redirects here, a client-rendered SPA.
// The raw HTML leads with an asset version (e.g. "15.0.3") followed by unrelated
// numbers, so the regex parser reads a false version; the real product version
// only appears after render. Each release renders a "Version X.Y.Z" heading,
// newest first — anchor on that heading text.
// Returns the latest version string, or "" if not found.
(() => {
  const h = [...document.querySelectorAll('h1,h2,h3,h4')]
    .map(e => e.textContent)
    .find(t => /Version\s+\d+\.\d+\.\d+/.test(t));
  return h ? (h.match(/(\d+\.\d+\.\d+)/) || [])[1] : '';
})()
