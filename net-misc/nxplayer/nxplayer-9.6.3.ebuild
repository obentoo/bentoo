# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker

MY_P="nomachine_${PV}_2"

DESCRIPTION="Client for NoMachine remote servers"
HOMEPAGE="https://www.nomachine.com"
SRC_URI="amd64? ( https://web9001.nomachine.com/download/$(ver_cut 1-2)/Linux/${MY_P}_amd64.deb )
	x86? ( https://web9001.nomachine.com/download/$(ver_cut 1-2)/Linux/${MY_P}_i386.deb )"
S="${WORKDIR}/usr/share/NX/packages/server"

LICENSE="nomachine"
SLOT="0"
KEYWORDS="-* ~amd64 ~x86"

RDEPEND="
	|| (
		sys-libs/libxcrypt[compat]
		sys-libs/glibc[crypt(-)]
	)
	dev-libs/glib:2
	dev-libs/openssl:0
"

QA_PREBUILT="*"
RESTRICT="bindist mirror strip"

src_install() {
	dodir /opt
	tar xozf nxrunner.tar.gz -C "${ED}"/opt || die
	tar xozf nxplayer.tar.gz -C "${ED}"/opt || die

	doenvd "${FILESDIR}"/50nxplayer
	dosym -r /opt/NX/bin/nxplayer /opt/bin/nxplayer
}
