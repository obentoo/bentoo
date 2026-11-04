# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{11..15} )

inherit meson-multilib python-any-r1 verify-sig

DESCRIPTION="EDID and DisplayID library"
HOMEPAGE="https://gitlab.freedesktop.org/emersion/libdisplay-info"
SRC_URI="https://gitlab.freedesktop.org/emersion/${PN}/-/releases/${PV}/downloads/${P}.tar.xz
	https://gitlab.freedesktop.org/emersion/${PN}/-/releases/${PV}/downloads/${P}.tar.xz.sig"

LICENSE="MIT"
SLOT="0/$(ver_cut 2)"
KEYWORDS="~amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ~ppc64 ~riscv ~sparc ~x86"

BDEPEND="
	${PYTHON_DEPS}
	sys-apps/hwdata
	virtual/pkgconfig
	verify-sig? ( sec-keys/openpgp-keys-emersion )
"

VERIFY_SIG_OPENPGP_KEY_PATH="/usr/share/openpgp-keys/emersion.asc"
