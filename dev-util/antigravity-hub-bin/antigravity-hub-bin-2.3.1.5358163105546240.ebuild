# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="Google Antigravity 2.0 standalone agent orchestration desktop app (binary release)"
HOMEPAGE="https://antigravity.google/"

MY_PV="${PV%.*}-${PV##*.}"
SRC_URI="amd64? ( https://storage.googleapis.com/antigravity-public/antigravity-hub/${MY_PV}/linux-x64/Antigravity.tar.gz -> ${PN}-${MY_PV}.tar.gz )"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="bindist mirror strip"

RDEPEND="
	app-accessibility/at-spi2-core
	app-crypt/libsecret
	dev-libs/glib
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/libpng
	net-print/cups
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libXcursor
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libXScrnSaver
	x11-libs/libXtst
	x11-libs/pango
	x11-misc/xdg-utils
"
DEPEND="${RDEPEND}"
BDEPEND=""

S="${WORKDIR}/Antigravity-x64"

QA_PREBUILT="*"

src_install() {
	local appdir="/opt/${PN}"

	dodir "${appdir}"
	cp -r "${S}"/. "${ED}${appdir}" || die "Failed to install application files"

	fperms 0755 "${appdir}/antigravity" "${appdir}/chrome_crashpad_handler"
	fperms 4755 "${appdir}/chrome-sandbox"

	dosym "${appdir}/antigravity" /usr/bin/antigravity-hub

	newicon "${FILESDIR}/${PN}.png" antigravity-hub.png

	cat > "${T}/${PN}.desktop" <<-EOF || die "Failed to write desktop file"
		[Desktop Entry]
		Name=Antigravity 2.0
		Comment=Google Antigravity agent orchestration hub
		Exec=/usr/bin/antigravity-hub %U
		Icon=antigravity-hub
		Terminal=false
		Type=Application
		Categories=Development;
		StartupWMClass=antigravity
	EOF

	insinto /usr/share/applications
	doins "${T}/${PN}.desktop"

	dodoc LICENSE.electron.txt
}

pkg_postinst() {
	xdg_pkg_postinst
}

pkg_postrm() {
	xdg_pkg_postrm
}
