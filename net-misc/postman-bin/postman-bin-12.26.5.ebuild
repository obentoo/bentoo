# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN=${PN/-bin/}

inherit desktop xdg

DESCRIPTION="API platform for building and using APIs"
HOMEPAGE="https://www.postman.com/"
SRC_URI="https://dl.pstmn.io/download/version/${PV}/linux64 -> ${P}.tar.gz"

LICENSE="all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"

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
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libXtst
	x11-libs/pango
	x11-misc/xdg-utils
"

RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

S="${WORKDIR}/Postman/app"

src_install() {
	insinto /opt/${MY_PN}
	doins -r *

	exeinto /opt/${MY_PN}
	doexe Postman
	doexe postman
	doexe chrome_crashpad_handler
	doexe chrome-sandbox
	fperms 4711 /opt/${MY_PN}/chrome-sandbox

	dosym /opt/${MY_PN}/Postman /usr/bin/${MY_PN}

	newicon resources/app/assets/icon.png postman.png

	make_desktop_entry "postman %U" \
		"Postman" \
		"postman" \
		"Development;Utility;" \
		"StartupWMClass=postman\nMimeType=x-scheme-handler/postman"
}
