# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop optfeature unpacker xdg

MY_PN="${PN%-bin}-desktop"

DESCRIPTION="Proton Lumo, a privacy-first AI assistant (Tauri desktop app)"
HOMEPAGE="
	https://lumo.proton.me/
	https://github.com/ProtonLumo/lumo-desktop
"
# The GitHub repository publishes no releases; Proton's own feed
# (proton.me/download/lumo/desktop/linux/v1/version.json) points here.
SRC_URI="
	amd64? (
		https://lumo.protondownload.com/linux/${PV}/Lumo_${PV}_amd64.deb
			-> ${P}-amd64.deb
	)
"
S="${WORKDIR}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="-* ~amd64"
# bindist: the app is GPL-3, but the binary statically links a few hundred
# Rust crates whose licenses nobody has enumerated, so it is not
# redistributed in packaged form.
# mirror: Gentoo mirrors carry no overlay distfiles; skip the lookup.
# strip: prebuilt binary, shipped as upstream built it.
RESTRICT="bindist mirror strip"

# lumo-desktop NEEDED libs, plus the tray library, which Tauri dlopen()s
# (libayatana-appindicator3.so.1) and the upstream .deb lists in Depends.
RDEPEND="
	dev-libs/glib:2
	dev-libs/libayatana-appindicator
	net-libs/libsoup:3.0
	net-libs/webkit-gtk:4.1
	sys-apps/dbus
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
"

QA_PREBUILT="*"

src_install() {
	# A single self-contained executable: Tauri embeds the web assets, so
	# there is no resource directory to keep next to it.
	dobin usr/bin/${MY_PN}

	# Upstream's entry is valid as shipped (Exec=lumo-desktop %u, and the
	# proton-lumo:// scheme handler used by the sign-in flow).
	domenu usr/share/applications/lumo.desktop

	local size
	for size in 32 128; do
		doicon -s ${size} "usr/share/icons/hicolor/${size}x${size}/apps/${MY_PN}.png"
	done
	# The .deb puts a 256x256-pixel image in 256x256@2, which hicolor reads as
	# 512 physical pixels. It goes in 256x256, the size it really is.
	doicon -s 256 "usr/share/icons/hicolor/256x256@2/apps/${MY_PN}.png"

	# Updater: the binary has tauri-plugin-updater built in, polling
	# lumo.protondownload.com/desktop/linux/latest.json and installing through
	# pkexec. Gentoo has no dpkg, so an accepted update fails instead of
	# overwriting files Portage owns. There is no runtime switch to turn the
	# check off, so it is left alone; update through Portage.
}

pkg_postinst() {
	xdg_pkg_postinst

	# The .deb Recommends gnome-keyring | kwalletd: account credentials go
	# through the Secret Service D-Bus API (keyring crate).
	optfeature "storing credentials in a keyring" virtual/secret-service
}
