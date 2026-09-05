# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# BENTOO-DIVERGENCE: INHERIT - unpacker, because series 10 ships a .deb where
# the 7.x in ::gentoo is a .tar.gz.
# BENTOO-DIVERGENCE: DEFINED_PHASES - unpack is exported by the unpacker eclass
# above; this ebuild defines no phase of its own.
inherit unpacker

# Build number: not derivable from PV, read it off the download page
MY_BUILD="1"
MY_P="nomachine-personal-edition_${PV}_${MY_BUILD}"

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
