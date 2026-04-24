# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="Management Software for MikroTik RouterOS"
HOMEPAGE="https://mikrotik.com/"
SRC_URI="https://download.mikrotik.com/routeros/winbox/${PV}/WinBox_Linux.zip -> ${P}.zip"
S="${WORKDIR}"

LICENSE="MikroTik"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="opt/winbox/WinBox"

RDEPEND="
	media-libs/fontconfig
	media-libs/freetype
	media-libs/libglvnd
	sys-apps/dbus
	virtual/zlib:=
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libxkbcommon[X]
	x11-libs/xcb-util-image
	x11-libs/xcb-util-keysyms
	x11-libs/xcb-util-renderutil
	x11-libs/xcb-util-wm
"
BDEPEND="app-arch/unzip"

src_install() {
	exeinto /opt/winbox
	doexe WinBox

	insinto /opt/winbox
	doins -r assets

	dosym -r /opt/winbox/WinBox /opt/bin/winbox

	newicon -s 256 assets/img/winbox.png winbox.png
	make_desktop_entry winbox WinBox winbox "Network;RemoteAccess;"
}
