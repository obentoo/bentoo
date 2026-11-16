# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 toolchain-funcs

MY_P="${PN}-python-${PV}"

DESCRIPTION="Python bindings for dev-libs/gbinder"
HOMEPAGE="https://github.com/waydroid/gbinder-python"
SRC_URI="https://github.com/waydroid/${PN}-python/archive/${PV}.tar.gz -> ${P}.gh.tar.gz"
S="${WORKDIR}/${MY_P}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="
	dev-libs/gbinder:=
	dev-libs/glib:2
	dev-libs/libglibutil
"
RDEPEND="${DEPEND}"
BDEPEND="
	dev-python/cython[${PYTHON_USEDEP}]
	virtual/pkgconfig
"

distutils_enable_tests import-check

src_prepare() {
	distutils-r1_src_prepare
	# setup.py calls a bare pkg-config
	grep -qF "'pkg-config --cflags --libs {}'" setup.py || die "setup.py pkg-config call changed"
	sed -i "s|'pkg-config --cflags|'$(tc-getPKG_CONFIG) --cflags|" setup.py || die
}
