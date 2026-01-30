# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

MY_BUILD="esr-bb18"
MY_PN="${PN%-bin}"

DESCRIPTION="Fine-tuned version of Mozilla Thunderbird with additional features"
HOMEPAGE="https://betterbird.eu/ https://github.com/Betterbird/thunderbird-patches/"
SRC_URI="https://www.betterbird.eu/downloads/LinuxArchive/${MY_PN}-${PV}${MY_BUILD}.en-US.linux-x86_64.tar.xz"

S="${WORKDIR}/${MY_PN}"

LICENSE="MPL-2.0 GPL-2 LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64"
IUSE="wayland"
RESTRICT="strip"

RDEPEND="
	app-accessibility/at-spi2-core:2
	dev-libs/atk
	dev-libs/dbus-glib
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/libpng:0
	sys-apps/dbus
	sys-libs/zlib
	virtual/freedesktop-icon-theme
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3[X]
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXcursor
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libXtst
	x11-libs/libxcb
	x11-libs/pango
	x11-libs/pixman
	wayland? (
		dev-libs/wayland
		x11-libs/gtk+:3[wayland]
	)
"

QA_PREBUILT="opt/${MY_PN}/*"

src_install() {
	local destdir="/opt/${MY_PN}"
	
	# Install all application files
	insinto "${destdir}"
	doins -r .
	
	# Create symlink: /usr/bin/betterbird-bin → /opt/betterbird/betterbird-bin
	dosym "../../${destdir}/${MY_PN}-bin" "/usr/bin/${PN}"
	
	# Install desktop file: betterbird-bin.desktop
	domenu "${FILESDIR}/${PN}.desktop"
	
	# Install icons using name without -bin suffix
	local size
	for size in 16 32 48 64 128 256; do
		newicon -s ${size} \
			"chrome/icons/default/default${size}.png" \
			"${MY_PN}.png"
	done
	
	# Set executable permissions for main binary
	fperms +x "${destdir}"/${MY_PN}-bin
	
	# Set permissions for utility binaries
	local util
	for util in glxtest vaapitest pingsender updater; do
		[[ -f "${ED}${destdir}/${util}" ]] && \
			fperms +x "${destdir}/${util}"
	done
	
	# Set permissions for shared libraries
	find "${ED}${destdir}" -type f \( -name '*.so' -o -name '*.so.*' \) \
		-exec chmod +x {} + || die
}

pkg_postinst() {
	xdg_pkg_postinst
	
	elog "Betterbird has been installed to ${EROOT}${destdir}"
	elog ""
	elog "To run Betterbird, execute: betterbird-bin"
	elog ""
	elog "Language pack XPIs must be downloaded and installed manually:"
	elog "  https://betterbird.eu/downloads/index.php"
	elog ""
	
	if use wayland; then
		elog "Wayland support is enabled via USE flag."
		elog "Set MOZ_ENABLE_WAYLAND=1 environment variable to use it:"
		elog "  export MOZ_ENABLE_WAYLAND=1"
		elog ""
	fi
	
	elog "Note: This is a binary package. For a compiled version,"
	elog "      consider using mail-client/betterbird instead."
}

pkg_postrm() {
	xdg_pkg_postrm
}