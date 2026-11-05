# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 2.28.4 ebuild, bumped to 2.28.5; python3_15 added.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT.
PYTHON_COMPAT=( python3_{11..15} )
inherit gnome.org meson-multilib python-any-r1

DESCRIPTION="C++ interface for the ATK library"
HOMEPAGE="https://gtkmm.gnome.org/en/index.html"

LICENSE="LGPL-2.1+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="gtk-doc"

DEPEND="
	>=dev-cpp/glibmm-2.46.2:2[gtk-doc?,${MULTILIB_USEDEP}]
	>=dev-libs/atk-2.18.0[${MULTILIB_USEDEP}]
	>=dev-libs/libsigc++-2.3.2:2[gtk-doc?,${MULTILIB_USEDEP}]
"
RDEPEND="${DEPEND}"
BDEPEND="
	virtual/pkgconfig
	gtk-doc? (
		>=dev-cpp/mm-common-1.0.4
		app-text/doxygen[dot]
		dev-libs/libxslt
	)
	${PYTHON_DEPS}
"

multilib_src_configure() {
	local emesonargs=(
		$(meson_native_use_bool gtk-doc build-documentation)
	)
	meson_src_configure
}
