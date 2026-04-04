# gentoo-dev Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a complete Claude Code skill for Gentoo ebuild development at `~/.claude/skills/gentoo-dev/`

**Architecture:** Orchestrator SKILL.md dispatches specialized sub-agents (creator, editor, bumper, maintainer, QA) with overlay-aware context injection via shell scripts and profile system.

**Tech Stack:** Markdown (SKILL.md, agents, references), Bash (scripts), ebuild templates, JSON (evals)

**Spec:** `docs/superpowers/specs/2026-04-04-gentoo-dev-skill-design.md`

---

## File Structure

```
~/.claude/skills/gentoo-dev/
├── SKILL.md                          # Orchestrator: routing, dispatch, gotchas
├── agents/
│   ├── ebuild-creator.md             # Sub-agent: create ebuilds from scratch
│   ├── ebuild-editor.md              # Sub-agent: modify existing ebuilds
│   ├── ebuild-bumper.md              # Sub-agent: version bumps
│   ├── overlay-maintainer.md         # Sub-agent: batch cleanup
│   └── qa-checker.md                 # Sub-agent: quality validation
├── references/
│   ├── eclass-guide.md               # Eclass reference by category
│   ├── dependency-syntax.md          # Dependency atom syntax
│   ├── language-ecosystems.md        # Go/Rust/Java/Python patterns
│   └── gotchas.md                    # Critical pitfalls with examples
├── scripts/
│   ├── detect-overlay.sh             # Dynamic context: overlay detection
│   └── quick-lint.sh                 # PostToolUse hook: fast ebuild lint
├── assets/
│   ├── profiles/
│   │   ├── bentoo.md                 # Bentoo overlay conventions
│   │   └── default.md               # Generic Gentoo conventions
│   └── templates/
│       ├── source-autotools.ebuild
│       ├── source-cmake.ebuild
│       ├── source-meson.ebuild
│       ├── source-cargo.ebuild
│       ├── source-go.ebuild
│       ├── source-python.ebuild
│       ├── binary-deb.ebuild
│       ├── binary-direct.ebuild
│       ├── binary-appimage.ebuild
│       ├── live-snapshot.ebuild
│       ├── gstreamer-plugin.ebuild
│       └── metadata.xml
└── evals/
    ├── evals.json
    └── trigger-queries.json
```

---

### Task 1: Directory Structure and Scripts

**Files:**
- Create: `~/.claude/skills/gentoo-dev/scripts/detect-overlay.sh`
- Create: `~/.claude/skills/gentoo-dev/scripts/quick-lint.sh`

- [ ] **Step 1: Create skill directory tree**

```bash
mkdir -p ~/.claude/skills/gentoo-dev/{agents,references,scripts,assets/{profiles,templates},evals}
```

- [ ] **Step 2: Write `detect-overlay.sh`**

Create `~/.claude/skills/gentoo-dev/scripts/detect-overlay.sh` -- walks up the directory tree looking for `metadata/layout.conf` + `profiles/repo_name`. Outputs overlay name, path, layout.conf contents, categories, custom eclasses. Used by `!` backtick syntax in SKILL.md for dynamic context injection.

Source code is in the spec at lines 381-419. Copy verbatim.

- [ ] **Step 3: Make detect-overlay.sh executable**

```bash
chmod +x ~/.claude/skills/gentoo-dev/scripts/detect-overlay.sh
```

- [ ] **Step 4: Test detect-overlay.sh**

```bash
cd ~/Projetos/git/bentoo/overlay && ~/.claude/skills/gentoo-dev/scripts/detect-overlay.sh
```

Expected: Output showing `Name: bentoo`, `Path: /home/otaku/Projetos/git/bentoo/overlay`, layout.conf contents, categories, and custom eclasses (brave.eclass, gstreamer-meson.eclass).

- [ ] **Step 5: Write `quick-lint.sh`**

Create `~/.claude/skills/gentoo-dev/scripts/quick-lint.sh` -- receives ebuild path as `$1`, checks: EAPI declared, copyright header, eapply_user in src_prepare, KEYWORDS empty for 9999, SLOT declared, LICENSE declared. Exit 2 on errors (blocks hook), exit 0 on clean/warnings.

Source code is in the spec at lines 426-490. Copy verbatim.

- [ ] **Step 6: Make quick-lint.sh executable**

```bash
chmod +x ~/.claude/skills/gentoo-dev/scripts/quick-lint.sh
```

- [ ] **Step 7: Test quick-lint.sh against a known-good ebuild**

```bash
~/.claude/skills/gentoo-dev/scripts/quick-lint.sh ~/Projetos/git/bentoo/overlay/dev-util/vulkan-headers/vulkan-headers-1.4.347_p20260403.ebuild
```

Expected: Exit 0, no errors.

- [ ] **Step 8: Test quick-lint.sh catches missing EAPI**

Create a temporary bad ebuild and verify the script catches it:

```bash
echo '# No EAPI here' > /tmp/test-bad.ebuild
~/.claude/skills/gentoo-dev/scripts/quick-lint.sh /tmp/test-bad.ebuild; echo "Exit: $?"
rm /tmp/test-bad.ebuild
```

Expected: `[ERROR] Missing EAPI declaration`, `[ERROR] Missing copyright header`, Exit: 2.

---

### Task 2: Overlay Profiles

**Files:**
- Create: `~/.claude/skills/gentoo-dev/assets/profiles/bentoo.md`
- Create: `~/.claude/skills/gentoo-dev/assets/profiles/default.md`

- [ ] **Step 1: Write bentoo.md profile**

Create `~/.claude/skills/gentoo-dev/assets/profiles/bentoo.md` with conventions extracted from the bentoo overlay analysis:

```markdown
# Bentoo Overlay Conventions

## Repository
- Name: `bentoo`
- Masters: `gentoo`
- thin-manifests: true
- sign-manifests: false

## Versioning
- Snapshots use `_p<YYYYMMDD>` suffix with `GIT_COMMIT=` or `COMMIT=` variable
- SRC_URI always renamed with `-> ${P}.tar.gz` when upstream tarball is not informative
- Live ebuilds use dual-mode: `if [[ ${PV} == *9999* ]]` block with git-r3, else pinned commit

## Keywords
- Primary: `~amd64`
- Secondary: `~arm64` when applicable
- Binary-only packages: `-* ~amd64 ~arm64`

## Naming
- `MY_PN` used when upstream name differs (e.g., `MY_PN=Vulkan-Headers`)
- `MY_P="${P/_/-}"` for upstream versions with hyphens instead of underscores
- `S="${WORKDIR}/${MY_PN}-${EGIT_COMMIT}"` for pinned commits

## Copyright
- `# Copyright 1999-<current_year> Gentoo Authors`

## Binary Packages
- Install to `/opt/<package-name>/`
- `QA_PREBUILT="*"`
- `RESTRICT="bindist mirror strip"`
- .deb packages: `inherit unpacker`
- Chromium-based apps: `inherit chromium-2`, use `chromium_remove_language_paks`
- Set SUID on chrome-sandbox: `fperms 4711 /opt/<name>/chrome-sandbox`
- PaX mark executables: `pax-mark m /opt/<name>/<binary>`
- Create symlink: `dosym ../<name>/bin/<binary> /opt/bin/<binary>`

## Desktop Apps
- Install icons at multiple sizes with `newicon -s ${size}`
- Generate .desktop files with corrected Exec and Icon paths
- Install bash completions with `newbashcomp`
- Install zsh completions with `newzshcomp`

## GStreamer
- Use custom eclass `gstreamer-meson` (supports meson.options for GStreamer 1.28.0+)

## Build Defaults
- EAPI=8 always
- Prefer `default` in src_prepare (applies PATCHES + eapply_user)
- Use `|| die` after every fallible command
```

- [ ] **Step 2: Write default.md profile**

Create `~/.claude/skills/gentoo-dev/assets/profiles/default.md`:

```markdown
# Generic Gentoo Overlay Conventions

## Repository
- Detect configuration via `metadata/layout.conf`
- Follow Gentoo devmanual strictly

## Versioning
- Standard Gentoo version scheme
- EAPI=8

## Keywords
- Default: `~amd64`
- Use `~arch` for new ebuilds (never commit straight to stable)

## Copyright
- `# Copyright 1999-<current_year> Gentoo Authors`
- `# Distributed under the terms of the GNU General Public License v2`

## Build Defaults
- Prefer `default` in src_prepare over explicit eapply_user
- SRC_URI with rename `->` only when necessary
- Test with `ebuild <path> manifest clean unpack compile install`

## Style
- Tabs for indentation (each tab = 4 spaces equivalent)
- No spaces around `=` in variable assignments
- Variable values must be ASCII only (GLEP 31)
- Only override phase functions when needed
```

---

### Task 3: Ebuild Templates (Source Builds)

**Files:**
- Create: `~/.claude/skills/gentoo-dev/assets/templates/source-autotools.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/source-cmake.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/source-meson.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/source-cargo.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/source-go.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/source-python.ebuild`

- [ ] **Step 1: Write source-autotools.ebuild template**

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"
SRC_URI="@@SRC_URI@@"

LICENSE="@@LICENSE@@"
SLOT="@@SLOT@@"
KEYWORDS="~amd64"
IUSE="@@IUSE@@"

DEPEND="@@DEPEND@@"
RDEPEND="${DEPEND}"
BDEPEND="@@BDEPEND@@"

src_configure() {
	local myeconfargs=(
		# $(use_enable feature)
		# $(use_with lib)
	)
	econf "${myeconfargs[@]}"
}

src_install() {
	default
	# Remove static libraries if not needed
	# find "${ED}" -name '*.la' -delete || die
}
```

- [ ] **Step 2: Write source-cmake.ebuild template**

Based on real vulkan-headers ebuild pattern:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# MY_PN=@@UPSTREAM_NAME@@  # Uncomment if upstream name differs
inherit cmake

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="@@GIT_URI@@"
	inherit git-r3
else
	EGIT_COMMIT="@@COMMIT@@"
	SRC_URI="@@SRC_URI_BASE@@/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64"
	S="${WORKDIR}/@@SOURCE_DIR@@"
fi

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"

LICENSE="@@LICENSE@@"
SLOT="@@SLOT@@"
IUSE="test"
RESTRICT="!test? ( test )"

DEPEND="@@DEPEND@@"
RDEPEND="${DEPEND}"
BDEPEND="@@BDEPEND@@"

src_configure() {
	local mycmakeargs=(
		-DBUILD_TESTING=$(usex test)
	)
	cmake_src_configure
}
```

- [ ] **Step 3: Write source-meson.ebuild template**

Based on real vulkan-loader pattern (cmake-multilib variant noted in comment):

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# MY_PN=@@UPSTREAM_NAME@@  # Uncomment if upstream name differs
inherit meson

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="@@GIT_URI@@"
	inherit git-r3
else
	EGIT_COMMIT="@@COMMIT@@"
	SRC_URI="@@SRC_URI_BASE@@/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64"
	S="${WORKDIR}/@@SOURCE_DIR@@"
fi

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"

LICENSE="@@LICENSE@@"
SLOT="@@SLOT@@"
IUSE="test"
RESTRICT="!test? ( test )"

DEPEND="@@DEPEND@@"
RDEPEND="${DEPEND}"
BDEPEND="
	virtual/pkgconfig
"

src_configure() {
	local emesonargs=(
		$(meson_feature test tests)
	)
	meson_src_configure
}
```

- [ ] **Step 4: Write source-cargo.ebuild template**

Based on real zed ebuild pattern:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
@@CRATES_LIST@@
"

RUST_MIN_VER="@@RUST_MIN_VER@@"

inherit cargo

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="@@GIT_URI@@"
	inherit git-r3
else
	SRC_URI="@@SRC_URI@@
		${CARGO_CRATE_URIS}
	"
	KEYWORDS="~amd64"
fi

# License for the package itself + dependent crates
LICENSE="@@LICENSE@@"
# Dependent licenses (generate with cargo-license)
LICENSE+=" @@CRATE_LICENSES@@"
SLOT="@@SLOT@@"
IUSE="@@IUSE@@"

DEPEND="@@DEPEND@@"
RDEPEND="${DEPEND}"
BDEPEND="
	virtual/pkgconfig
"

# QA_FLAGS_IGNORED="usr/bin/@@BINARY@@"

src_compile() {
	cargo_src_compile
}

src_install() {
	dobin target/release/@@BINARY@@
	einstalldocs
}
```

- [ ] **Step 5: Write source-go.ebuild template**

Based on real docker-buildx ebuild:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="@@GIT_URI@@"
else
	SRC_URI="@@SRC_URI@@"
	KEYWORDS="~amd64"
	S="${WORKDIR}/@@SOURCE_DIR@@"
fi

LICENSE="@@LICENSE@@"
# Dependent licenses
LICENSE+=" @@MODULE_LICENSES@@"
SLOT="@@SLOT@@"

RDEPEND="@@RDEPEND@@"

src_compile() {
	local go_ldflags=(
		"-linkmode=external"
		-X "@@VERSION_PKG@@.Version=${PV}"
		-X "@@VERSION_PKG@@.Revision=gentoo"
	)
	ego build -o @@BINARY@@ -ldflags "${go_ldflags[*]}" @@BUILD_TARGET@@
}

src_install() {
	dobin @@BINARY@@
	einstalldocs
}
```

- [ ] **Step 6: Write source-python.ebuild template**

Based on gst-python and standard distutils-r1 patterns:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=@@BUILD_BACKEND@@
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"
SRC_URI="@@SRC_URI@@"

LICENSE="@@LICENSE@@"
SLOT="@@SLOT@@"
KEYWORDS="~amd64"

RDEPEND="@@RDEPEND@@"
BDEPEND="
	test? ( @@TEST_DEPS@@ )
"

distutils_enable_tests pytest
```

---

### Task 4: Ebuild Templates (Binary & Special)

**Files:**
- Create: `~/.claude/skills/gentoo-dev/assets/templates/binary-deb.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/binary-direct.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/binary-appimage.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/live-snapshot.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/gstreamer-plugin.ebuild`
- Create: `~/.claude/skills/gentoo-dev/assets/templates/metadata.xml`

- [ ] **Step 1: Write binary-deb.ebuild template**

Based on real cursor ebuild:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop pax-utils unpacker xdg

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"
SRC_URI="
	amd64? ( @@DEB_URL_AMD64@@ -> ${P}-amd64.deb )
	arm64? ( @@DEB_URL_ARM64@@ -> ${P}-arm64.deb )
"
S="${WORKDIR}"

LICENSE="@@LICENSE@@"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="@@IUSE@@"
RESTRICT="bindist mirror strip"

RDEPEND="
	@@RDEPEND@@
"

QA_PREBUILT="*"

src_install() {
	# Install application to /opt
	dodir /opt/@@PKG_NAME@@
	cp -ar usr/share/@@PKG_NAME@@/. "${D}/opt/@@PKG_NAME@@/" || die

	# Sandbox and PaX
	fperms 4711 /opt/@@PKG_NAME@@/chrome-sandbox
	pax-mark m /opt/@@PKG_NAME@@/@@BINARY@@

	# Symlink binary
	dosym ../@@PKG_NAME@@/bin/@@BINARY@@ /opt/bin/@@BINARY@@

	# Desktop integration
	domenu usr/share/applications/@@PKG_NAME@@.desktop
	local size
	for size in 16 24 32 48 64 128 256 512; do
		newicon -s "${size}" usr/share/pixmaps/@@ICON_FILE@@ @@PKG_NAME@@.png
	done
}

pkg_postinst() {
	xdg_pkg_postinst
}
```

- [ ] **Step 2: Write binary-direct.ebuild template**

Based on real claude-code ebuild:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"
SRC_URI="
	amd64? ( @@BINARY_URL_AMD64@@ -> @@BINARY_NAME@@-amd64-${PV} )
	arm64? ( @@BINARY_URL_ARM64@@ -> @@BINARY_NAME@@-arm64-${PV} )
"
S="${WORKDIR}"

LICENSE="@@LICENSE@@"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="opt/bin/@@BINARY_NAME@@"

RDEPEND="@@RDEPEND@@"

src_compile() {
	:
}

src_install() {
	exeinto /opt/bin
	newexe "${DISTDIR}/${A[0]}" @@BINARY_NAME@@
}
```

- [ ] **Step 3: Write binary-appimage.ebuild template**

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"
SRC_URI="@@APPIMAGE_URL@@ -> ${P}.AppImage"
S="${WORKDIR}"

LICENSE="@@LICENSE@@"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

RDEPEND="
	sys-libs/zlib
	x11-libs/libX11
"

src_unpack() {
	cp "${DISTDIR}/${P}.AppImage" "${WORKDIR}/" || die
	chmod +x "${P}.AppImage" || die
	"./${P}.AppImage" --appimage-extract || die
	S="${WORKDIR}/squashfs-root"
}

src_install() {
	dodir /opt/@@PKG_NAME@@
	cp -ar . "${D}/opt/@@PKG_NAME@@/" || die

	dosym ../@@PKG_NAME@@/@@BINARY@@ /opt/bin/@@BINARY@@

	# Desktop integration (adapt icon/desktop paths from AppImage contents)
	# domenu @@PKG_NAME@@.desktop
	# newicon @@ICON_FILE@@ @@PKG_NAME@@.png
}
```

- [ ] **Step 4: Write live-snapshot.ebuild template**

Based on real vulkan-headers/mesa dual-mode pattern:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# MY_PN=@@UPSTREAM_NAME@@  # Uncomment if upstream name differs
inherit @@INHERIT@@

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="@@GIT_URI@@"
	inherit git-r3
else
	GIT_COMMIT="@@COMMIT@@"
	SRC_URI="@@SRC_URI_BASE@@/archive/${GIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64"
	S="${WORKDIR}/@@SOURCE_DIR@@"
fi

DESCRIPTION="@@DESCRIPTION@@"
HOMEPAGE="@@HOMEPAGE@@"

LICENSE="@@LICENSE@@"
SLOT="@@SLOT@@"
IUSE="@@IUSE@@"

DEPEND="@@DEPEND@@"
RDEPEND="${DEPEND}"
BDEPEND="@@BDEPEND@@"
```

- [ ] **Step 5: Write gstreamer-plugin.ebuild template**

Based on real gst-plugins-a52dec:

```bash
# Copyright 1999-@@YEAR@@ Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE=@@GST_MODULE@@

inherit gstreamer-meson

DESCRIPTION="@@DESCRIPTION@@"
KEYWORDS="~amd64 ~arm ~arm64"
IUSE="+orc"

RDEPEND="
	@@RDEPEND@@
	orc? ( >=dev-lang/orc-0.4.33[${MULTILIB_USEDEP}] )
"
DEPEND="${RDEPEND}"

multilib_src_configure() {
	local emesonargs=(
		@@MESON_ARGS@@
	)
	gstreamer_multilib_src_configure
}
```

- [ ] **Step 6: Write metadata.xml template**

Based on real cursor and mesa metadata.xml:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE pkgmetadata SYSTEM "https://www.gentoo.org/dtd/metadata.dtd">
<pkgmetadata>
	<maintainer type="@@MAINTAINER_TYPE@@">
		<email>@@MAINTAINER_EMAIL@@</email>
		<name>@@MAINTAINER_NAME@@</name>
	</maintainer>
	<!-- Uncomment and add USE flag descriptions if IUSE is non-empty
	<use>
		<flag name="@@FLAG@@">@@FLAG_DESCRIPTION@@</flag>
	</use>
	-->
	<!-- Uncomment and set upstream tracking if applicable
	<upstream>
		<remote-id type="github">@@OWNER@@/@@REPO@@</remote-id>
	</upstream>
	-->
</pkgmetadata>
```

---

### Task 5: Reference Documents

**Files:**
- Create: `~/.claude/skills/gentoo-dev/references/gotchas.md`
- Create: `~/.claude/skills/gentoo-dev/references/eclass-guide.md`
- Create: `~/.claude/skills/gentoo-dev/references/dependency-syntax.md`
- Create: `~/.claude/skills/gentoo-dev/references/language-ecosystems.md`

- [ ] **Step 1: Write gotchas.md**

Full gotchas list with code examples for each. Expand the 10-item summary from the spec into detailed entries with before/after code showing the wrong way and right way. Include real examples from the bentoo overlay where possible.

Key entries:
1. `eapply_user` / `default` in src_prepare -- show wrong (missing) vs right
2. `|| die` -- show which commands need it and which don't (EAPI 8 builtins auto-die)
3. KEYWORDS empty for 9999 -- show `KEYWORDS=""` vs live block pattern
4. `S=` mismatch -- show `MY_PN` pattern from vulkan-headers
5. SRC_URI rename `->` -- show the pattern
6. `QA_PREBUILT` + `RESTRICT="strip"` -- show binary package requirements
7. Copyright + EAPI ordering -- show correct header
8. thin-manifests -- explain DIST-only entries
9. `default` in src_prepare -- explain it applies PATCHES + eapply_user
10. `MY_P`/`MY_PN` -- show pattern from vulkan-headers and mesa

- [ ] **Step 2: Write eclass-guide.md**

Organized by category. For each eclass: name, when to use, key variables, key functions, minimal example. Cover:
- Build systems: cmake, meson, autotools (econf), cargo, go-module, distutils-r1
- VCS: git-r3
- Binary: unpacker, chromium-2, verify-sig
- Python: python-any-r1, python-single-r1, python-r1
- Multilib: multilib-minimal, cmake-multilib, meson-multilib
- Desktop: desktop, xdg, pax-utils, shell-completion, optfeature
- LLVM: llvm-r1
- Rust: rust-toolchain, cargo
- Utility: flag-o-matic, toolchain-funcs, linux-info, savedconfig

Use real examples from the bentoo overlay for each.

- [ ] **Step 3: Write dependency-syntax.md**

Compact reference:
- Operators: `>=`, `>`, `=`, `<=`, `<`, `~`, `=...*`
- USE deps: `pkg[use1,-use2,use3(+)]`
- Slot deps: `:2`, `:=`, `:2=`, `:*`
- Subslots: `SLOT="0/16.1"`
- Blockers: `!pkg`, `!!pkg`
- Conditionals: `use? ( atoms )`, `|| ( a b )`
- DEPEND vs RDEPEND vs BDEPEND vs IDEPEND
- REQUIRED_USE: `||`, `??`, `^^`, `a? ( b )`
- Multilib: `${MULTILIB_USEDEP}` pattern
- Python: `${PYTHON_USEDEP}`, `${PYTHON_DEPS}`
- LLVM: `llvm_gen_dep` pattern

- [ ] **Step 4: Write language-ecosystems.md**

Patterns per language with gotchas:
- **Go**: go-module, EGO_SUM vs vendor, `ego build`, ldflags version injection, `RESTRICT="test"` patterns
- **Rust**: CRATES variable, CARGO_CRATE_URIS, pycargoebuild, RUST_MIN_VER, workspace builds, QA_FLAGS_IGNORED
- **Java**: java-pkg-2, java-pkg-simple, JAVA_SRC_DIR, virtual/jdk slot deps
- **Python**: PYTHON_COMPAT, DISTUTILS_USE_PEP517 (setuptools, flit, hatchling, poetry), python_foreach_impl, distutils_enable_tests
- **Ruby**: USE_RUBY, ruby-fakegem, gem2ebuild
- **Perl**: perl-module, MODULE_AUTHOR, CPAN integration
- **Electron/Node**: Binary repack pattern (never compile node natively), chromium-2 eclass, pax-mark, chrome-sandbox SUID

---

### Task 6: Sub-agents

**Files:**
- Create: `~/.claude/skills/gentoo-dev/agents/ebuild-creator.md`
- Create: `~/.claude/skills/gentoo-dev/agents/ebuild-editor.md`
- Create: `~/.claude/skills/gentoo-dev/agents/ebuild-bumper.md`
- Create: `~/.claude/skills/gentoo-dev/agents/overlay-maintainer.md`
- Create: `~/.claude/skills/gentoo-dev/agents/qa-checker.md`

- [ ] **Step 1: Write ebuild-creator.md**

Frontmatter:
```yaml
---
name: ebuild-creator
description: >
  Creates new Gentoo ebuilds from scratch. Analyzes upstream source to
  determine build system, dependencies, and license. Selects appropriate
  template and generates ebuild, metadata.xml, and Manifest.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 50
effort: max
---
```

Body: Full protocol from spec (7 steps: analyze upstream, select template, generate ebuild, generate metadata.xml, create directory, generate Manifest, report). Include reference loading conditions. Include the 10 inline gotchas. Include instructions to read templates from `${CLAUDE_SKILL_DIR}/assets/templates/` and adapt to the overlay profile passed in the dispatch prompt. Instruct to read eclass-guide.md and language-ecosystems.md when relevant.

- [ ] **Step 2: Write ebuild-editor.md**

Frontmatter:
```yaml
---
name: ebuild-editor
description: >
  Modifies existing Gentoo ebuilds with structural awareness. Ensures
  consistency across IUSE, dependencies, metadata.xml, and phase functions
  when making changes.
model: inherit
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 50
effort: max
---
```

Body: Full protocol from spec (6 steps: read, impact analysis, apply, verify consistency, Manifest, report). Include consistency checklist (USE flag -> IUSE + deps + metadata.xml, dependency -> correct type, patch -> files/ + PATCHES, SRC_URI -> Manifest). Include gotchas inline. Include reference loading conditions.

- [ ] **Step 3: Write ebuild-bumper.md**

Frontmatter:
```yaml
---
name: ebuild-bumper
description: >
  Bumps Gentoo ebuild versions. Copies previous ebuild as base, updates
  version, commit hash, SRC_URI, and regenerates Manifest. Handles
  snapshot (_p<date>) and standard version bumps.
model: sonnet
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 30
effort: high
---
```

Body: Full protocol from spec (6 steps: identify, copy, edit, remove old, Manifest, report). Include specific instructions for snapshot bumps (`_p<YYYYMMDD>`, GIT_COMMIT update) vs standard bumps. Include gotchas relevant to bumping (S= mismatch, SRC_URI rename).

- [ ] **Step 4: Write overlay-maintainer.md**

Frontmatter:
```yaml
---
name: overlay-maintainer
description: >
  Maintains Gentoo overlay health. Removes old ebuild versions, regenerates
  Manifests in batch, cleans stale DIST entries, and reports overlay status.
model: sonnet
tools: Read, Write, Edit, Bash, Glob, Grep
maxTurns: 40
effort: high
---
```

Body: Full protocol from spec (3 steps: scan, act, report). Include specific scanning patterns (multiple versions, orphan Manifest entries, missing metadata.xml). Include safe deletion protocol (verify latest version exists before removing old).

- [ ] **Step 5: Write qa-checker.md**

Frontmatter:
```yaml
---
name: qa-checker
description: >
  Validates Gentoo ebuild quality. Checks EAPI, copyright, die statements,
  eapply_user, KEYWORDS, IUSE consistency, metadata.xml, and Manifest.
  Runs pkgcheck if available.
model: haiku
tools: Read, Bash, Glob, Grep
maxTurns: 20
effort: medium
---
```

Body: Full protocol from spec (4 steps: receive, lint, pkgcheck, report). Include all 10 check items. Specify output format: `[ERROR|WARNING|INFO] description` with summary count. Specify stdout-only output (no file writes). Include pkgcheck fallback: check `command -v pkgcheck` before running.

---

### Task 7: SKILL.md (Orchestrator)

**Files:**
- Create: `~/.claude/skills/gentoo-dev/SKILL.md`

- [ ] **Step 1: Write SKILL.md frontmatter**

Copy the exact frontmatter from the spec (lines 67-128). This includes: name, description (with trigger phrases in EN/PT), allowed-tools (YAML list), effort, compatibility, argument-hint, metadata, hooks (PostToolUse: 3 hooks + Stop: 1 hook).

- [ ] **Step 2: Write SKILL.md body -- Overlay Context section**

Dynamic context injection:
```markdown
## Overlay Context

!`bash ${CLAUDE_SKILL_DIR}/scripts/detect-overlay.sh 2>/dev/null || echo "No overlay detected"`
```

Plus instructions to load the matching profile from `assets/profiles/`.

- [ ] **Step 3: Write SKILL.md body -- Command Routing section**

The `$ARGUMENTS` parsing table from spec (lines 150-169). Include natural language routing for when invoked without `/gentoo-dev` prefix.

- [ ] **Step 4: Write SKILL.md body -- Profile Loading section**

Instructions to match `repo_name` -> profile file, load it, and pass as context to sub-agents.

- [ ] **Step 5: Write SKILL.md body -- Dispatch Protocol section**

How to prepare the sub-agent prompt: task, package, profile content, gotchas, template path, user context.

- [ ] **Step 6: Write SKILL.md body -- Gotchas section (inline)**

The 10 critical gotchas from spec (lines 196-205). These travel with every sub-agent dispatch.

- [ ] **Step 7: Write SKILL.md body -- Reference Loading Conditions section**

The 4 progressive disclosure rules from spec (lines 210-215).

- [ ] **Step 8: Verify SKILL.md is under 500 lines**

```bash
wc -l ~/.claude/skills/gentoo-dev/SKILL.md
```

Expected: Under 500 lines. If over, move verbose sections to references.

---

### Task 8: Evals

**Files:**
- Create: `~/.claude/skills/gentoo-dev/evals/trigger-queries.json`
- Create: `~/.claude/skills/gentoo-dev/evals/evals.json`

- [ ] **Step 1: Write trigger-queries.json**

JSON array with should-trigger and should-not-trigger queries from the spec (lines 559-583).

```json
{
  "should_trigger": [
    "create an ebuild for package X",
    "bump mesa to version 26.0.5",
    "add wayland USE flag to cursor ebuild",
    "clean old versions from dev-util/glslang",
    "run QA check on the new ebuild",
    "criar ebuild para o pacote Y",
    "atualizar brave-browser para 1.89",
    "gerar Manifest para media-libs/mesa",
    "remover versões antigas do overlay",
    "editar as dependências do qemu",
    "add a patch to fix build with gcc-15",
    "write metadata.xml for new package"
  ],
  "should_not_trigger": [
    "explain what USE flags are",
    "how does Portage work?",
    "compile this C++ file",
    "create a Python script",
    "fix this JavaScript bug",
    "what is an eclass?",
    "install mesa on my system",
    "run emerge --sync",
    "help me configure make.conf",
    "review this pull request"
  ]
}
```

- [ ] **Step 2: Write evals.json**

JSON array with the 6 test cases from spec (lines 603-616), each with `name`, `prompt`, and `assertions` array.

---

### Task 9: Smoke Test

- [ ] **Step 1: Verify all 28 files exist**

```bash
find ~/.claude/skills/gentoo-dev/ -type f | wc -l
```

Expected: 28

- [ ] **Step 2: Verify scripts are executable**

```bash
ls -la ~/.claude/skills/gentoo-dev/scripts/
```

Expected: Both scripts have `x` permission.

- [ ] **Step 3: Test detect-overlay.sh in the bentoo overlay**

```bash
cd ~/Projetos/git/bentoo/overlay && ~/.claude/skills/gentoo-dev/scripts/detect-overlay.sh
```

Expected: Detects bentoo overlay with correct info.

- [ ] **Step 4: Test quick-lint.sh against a real ebuild**

```bash
~/.claude/skills/gentoo-dev/scripts/quick-lint.sh ~/Projetos/git/bentoo/overlay/app-editors/cursor/cursor-3.0.9.ebuild
```

Expected: Clean pass (exit 0).

- [ ] **Step 5: Verify SKILL.md frontmatter parses correctly**

```bash
head -130 ~/.claude/skills/gentoo-dev/SKILL.md
```

Expected: Valid YAML frontmatter between `---` markers with all required fields.

- [ ] **Step 6: Verify SKILL.md is under 500 lines**

```bash
wc -l ~/.claude/skills/gentoo-dev/SKILL.md
```

Expected: Under 500.
