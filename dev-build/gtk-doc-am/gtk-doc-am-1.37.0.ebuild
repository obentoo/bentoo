# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
# Based on ::gentoo's 1.36.1 ebuild, bumped to 1.37.0 because dev-util/gtk-doc
# BDEPENDs on ~dev-build/gtk-doc-am-${PV}; buildsystems/autotools/gtk-doc.m4 is
# unchanged between 1.36.1 and 1.37.0. Drop this copy once ::gentoo has 1.37.0.
# BENTOO-DIVERGENCE: KEYWORDS - overlay baseline (~amd64 only) for a version ::gentoo does not carry.
GNOME_ORG_MODULE="gtk-doc"

inherit gnome.org

DESCRIPTION="Automake files from gtk-doc"
HOMEPAGE="https://gitlab.gnome.org/GNOME/gtk-doc"

LICENSE="GPL-2+ FDL-1.1"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="!<dev-util/gtk-doc-${PV}"
PDEPEND="virtual/pkgconfig"

# This ebuild doesn't even compile anything, causing tests to fail when updating (bug #316071)
RESTRICT="test"

src_configure() {
	:
}

src_compile() {
	:
}

src_install() {
	insinto /usr/share/aclocal
	doins buildsystems/autotools/gtk-doc.m4
}
