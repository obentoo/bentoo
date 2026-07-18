# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg-utils

# Upstream rebrand: zadam/Trilium -> TriliumNext/Trilium (notes app forked
# after the original project was archived). Asset prefix is "TriliumNotes",
# but the archive unpacks to a directory named "Trilium Notes-linux-x64".
MY_P="TriliumNotes-v${PV}-linux-x64"

DESCRIPTION="TriliumNext Notes - hierarchical note taking application"
HOMEPAGE="https://github.com/TriliumNext/Trilium"
SRC_URI="https://github.com/TriliumNext/Trilium/releases/download/v${PV}/${MY_P}.zip
	-> ${P}.zip"

S="${WORKDIR}/Trilium Notes-linux-x64"

LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="-* ~amd64"

RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

BDEPEND="
	app-arch/unzip
"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
"

src_install() {
	dodir /opt/trilium
	cp -r "${S}/." "${ED}/opt/trilium/" || die

	# Main binary is named "trilium" inside the archive
	fperms +x /opt/trilium/trilium
	if [[ -f "${ED}/opt/trilium/chrome-sandbox" ]]; then
		fperms 4711 /opt/trilium/chrome-sandbox
	fi

	dosym -r /opt/trilium/trilium /usr/bin/trilium

	make_desktop_entry trilium "Trilium Notes" trilium "Office;Utility;" \
		"StartupWMClass=Trilium Notes"

	# Try to install icon if shipped in the bundle
	local icon
	for icon in icon.png trilium.png resources/icon.png; do
		if [[ -f "${S}/${icon}" ]]; then
			newicon "${S}/${icon}" trilium.png
			break
		fi
	done
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update
	xdg_mimeinfo_database_update
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
	xdg_mimeinfo_database_update
}
