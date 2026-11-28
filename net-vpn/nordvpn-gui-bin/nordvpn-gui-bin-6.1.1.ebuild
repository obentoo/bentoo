# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker xdg

MY_PN="${PN%-bin}"

DESCRIPTION="Graphical interface for the NordVPN daemon (prebuilt Flutter app)"
HOMEPAGE="https://nordvpn.com/download/linux/
	https://github.com/NordSecurity/nordvpn-linux"
SRC_URI="https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/n/${MY_PN}/${MY_PN}_${PV}_amd64.deb
	-> ${P}-amd64.deb"
S="${WORKDIR}"

# GPL-3 for the app (gui/ in nordvpn-linux); BSD for the Flutter engine.
LICENSE="GPL-3 BSD"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

# The .deb declares "Depends: nordvpn (= ${PV})": the GUI talks to nordvpnd
# over gRPC and upstream ships both from the same commit.  Libraries taken
# from readelf -d of every ELF in the 5.4.1 payload.
RDEPEND="
	~net-vpn/nordvpn-bin-${PV}
	app-accessibility/at-spi2-core:2
	dev-libs/glib:2
	media-libs/fontconfig
	media-libs/harfbuzz:=
	media-libs/libepoxy
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/pango
"

QA_PREBUILT="*"

src_install() {
	insinto /opt/${MY_PN}
	doins -r opt/${MY_PN}/{data,lib}
	exeinto /opt/${MY_PN}
	doexe opt/${MY_PN}/${MY_PN}
	dosym -r /opt/${MY_PN}/${MY_PN} /usr/bin/${MY_PN}

	insinto /usr/share
	doins -r usr/share/{applications,icons}
}
