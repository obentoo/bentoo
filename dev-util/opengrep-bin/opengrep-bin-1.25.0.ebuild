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
	amd64? (
		elibc_glibc? ( ${URLPREFIX}/opengrep_manylinux_x86 -> ${P}-x86_64-linux-gnu )
		elibc_musl? ( ${URLPREFIX}/opengrep_musllinux_x86 -> ${P}-x86_64-linux-musl )
	)
	arm64? (
		elibc_glibc? ( ${URLPREFIX}/opengrep_manylinux_aarch64 -> ${P}-aarch64-linux-gnu )
		elibc_musl? ( ${URLPREFIX}/opengrep_musllinux_aarch64 -> ${P}-aarch64-linux-musl )
	)
"
S="${WORKDIR}"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="strip"

QA_PREBUILT="usr/bin/opengrep"

DEPEND="
	!dev-util/opengrep
	elibc_glibc? ( sys-libs/glibc )
	elibc_musl? ( sys-libs/musl )
"
RDEPEND="${DEPEND}"

src_unpack() {
	# The upstream asset is a bare, self-contained ELF executable with no
	# extension: there is nothing to unpack.
	:
}

src_install() {
	local myarch mylibc

	if use amd64; then
		myarch="x86_64"
	elif use arm64; then
		myarch="aarch64"
	else
		die "Unsupported architecture"
	fi

	if use elibc_glibc; then
		mylibc="gnu"
	elif use elibc_musl; then
		mylibc="musl"
	else
		die "Unsupported libc"
	fi

	newbin "${DISTDIR}/${P}-${myarch}-linux-${mylibc}" opengrep
}
