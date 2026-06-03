// Windsurf / Devin Desktop version probe for the bentoolkit autoupdate "script" parser.
// Runs in a headless browser on https://docs.devin.ai/desktop/changelog
//
// Windsurf rebranded to "Devin Desktop": windsurf.com/changelog now 308-redirects
// to this Mintlify SPA. The raw HTML only exposes an asset version (e.g. "7.2.0"),
// so the regex/html parsers read a false version; the real product version only
// appears after the page renders. Each release block renders a "Download X.Y.Z"
// label, newest first — anchor on that to skip the bundled Devin Local agent
// version (e.g. "2026.5.26") and any asset noise.
// Returns the latest version string, or "" if not found.
(() => {
  const m = document.body.innerText.match(/Download\s+(\d+\.\d+\.\d+)/);
  return m ? m[1] : '';
})()
