# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{12..15} )
inherit gnome.org python-any-r1 meson

DESCRIPTION="Build infrastructure and utilities for GNOME C++ bindings"
HOMEPAGE="https://gtkmm.gnome.org/en/index.html"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~mips ppc ppc64 ~riscv ~sparc x86"

BDEPEND="${PYTHON_DEPS}"

src_prepare() {
	default

	# Include project version in docdir name
	sed -i -e "s:^install_docdir.*:& + '-' + meson.project_version():" meson.build || die
}

src_configure(){
	local emesonargs=(
		-Duse-network=false
	)
	meson_src_configure
}
