# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

MY_PN="${PN%-bin}"

DESCRIPTION="CC Switch, a GUI to switch between Claude Code, Codex and Gemini CLI accounts"
HOMEPAGE="https://github.com/farion1231/cc-switch"
CCS_BASE="https://github.com/farion1231/cc-switch/releases/download/v${PV}"
# .deb rather than the AppImage: same application, an eighth of the size
# (12 MB against 88 MB), because the AppImage carries its own runtime.
SRC_URI="
	amd64? (
		${CCS_BASE}/CC-Switch-v${PV}-Linux-x86_64.deb
			-> ${P}-amd64.deb
	)
	arm64? (
		${CCS_BASE}/CC-Switch-v${PV}-Linux-arm64.deb
			-> ${P}-arm64.deb
	)
"
S="${WORKDIR}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

# Tauri application: the webview is the system WebKitGTK, not a bundled one.
RDEPEND="
	net-libs/libsoup:3.0
	net-libs/webkit-gtk:4.1
	x11-libs/gtk+:3
"

QA_PREBUILT="*"

src_unpack() {
	unpack_deb "${A}"
}

src_install() {
	dobin usr/bin/${MY_PN}

	local size
	for size in 32 128; do
		doicon -s ${size} "usr/share/icons/hicolor/${size}x${size}/apps/${MY_PN}.png"
	done
	# 256x256@2 is the HiDPI variant; doicon -s does not take the @2 suffix,
	# so it is placed by hand rather than dropped.
	insinto /usr/share/icons/hicolor/256x256@2/apps
	doins "usr/share/icons/hicolor/256x256@2/apps/${MY_PN}.png"

	# Upstream's desktop entry needs two fixes: the file name contains a
	# space, and Categories= is present but EMPTY, which is invalid and makes
	# the entry unsortable in menus. Only ONE main category is used:
	# desktop-file-validate warns that two would list the app twice in menus.
	sed -e 's|^Categories=$|Categories=Development;|' \
		"usr/share/applications/CC Switch.desktop" > "${T}/${MY_PN}.desktop" || die
	grep -q '^Categories=Development;$' "${T}/${MY_PN}.desktop" ||
		die "Categories= was not filled in; upstream entry may have changed"
	domenu "${T}/${MY_PN}.desktop"
}
