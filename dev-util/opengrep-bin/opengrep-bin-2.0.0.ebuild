# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Open-source static code analysis engine, LGPL fork of Semgrep CE"
HOMEPAGE="
	https://www.opengrep.dev/
	https://github.com/opengrep/opengrep
"

URLPREFIX="https://github.com/opengrep/opengrep/releases/download/v${PV}"
SRC_URI="
	amd64? ( ${URLPREFIX}/opengrep_linux_x86 -> ${P}-x86_64-linux )
"
S="${WORKDIR}"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="strip"

QA_PREBUILT="usr/bin/opengrep"

# 2.0.0 ships one statically linked ELF for every libc (upstream dropped the
# manylinux/musllinux pair), so there is no libc dependency left to state.
RDEPEND="!dev-util/opengrep"

src_unpack() {
	# The upstream asset is a bare, self-contained ELF executable with no
	# extension: there is nothing to unpack.
	:
}

src_install() {
	local myarch

	if use amd64; then
		myarch="x86_64"
	else
		die "Unsupported architecture"
	fi

	newbin "${DISTDIR}/${P}-${myarch}-linux" opengrep
}
