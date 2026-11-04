# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{12..15} )
inherit gnome.org meson-multilib python-any-r1

DESCRIPTION="C++ interface for pango"
HOMEPAGE="https://gtkmm.gnome.org/en/index.html"

LICENSE="LGPL-2.1+"
SLOT="1.4"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~ppc ~ppc64 ~riscv ~sparc ~x86"
IUSE="gtk-doc"

RDEPEND="
	>=dev-cpp/cairomm-1.2.2:0[gtk-doc?,${MULTILIB_USEDEP}]
	>=dev-cpp/glibmm-2.48.0:2[gtk-doc?,${MULTILIB_USEDEP}]
	dev-libs/libsigc++:2[gtk-doc?,${MULTILIB_USEDEP}]
	>=x11-libs/pango-1.45.1[${MULTILIB_USEDEP}]
"
DEPEND="${RDEPEND}"
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
		-Dmaintainer-mode=false
		$(meson_native_use_bool gtk-doc build-documentation)
	)
	meson_src_configure
}

multilib_src_install_all() {
	if use gtk-doc; then
		mkdir -p "${ED}"/usr/share/gtk-doc/html/ || die
		mv "${ED}"/usr/share/doc/pangomm-1.4 "${ED}"/usr/share/gtk-doc/html/ || die
	fi
}
