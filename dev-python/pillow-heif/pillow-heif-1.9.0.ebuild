# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=setuptools
PYPI_PN="pillow_heif"
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="Pillow plugin for HEIF/HEIC/AVIF images, backed by libheif"
HOMEPAGE="
	https://github.com/bigcat88/pillow_heif/
	https://pypi.org/project/pillow-heif/
"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64"

# _pillow_heif.c refuses to compile below LIBHEIF_HAVE_VERSION(1,23,4).
# setup.py locates the system libheif through pkg-config; the bundled
# libheif/build_libs.py is only used for upstream's wheel CI and is never
# called on Linux.
DEPEND="
	>=media-libs/libheif-1.23.4:=
"
RDEPEND="
	${DEPEND}
	>=dev-python/pillow-11.1.0[${PYTHON_USEDEP}]
"
BDEPEND="
	virtual/pkgconfig
	test? (
		dev-python/defusedxml[${PYTHON_USEDEP}]
		dev-python/packaging[${PYTHON_USEDEP}]
	)
"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

python_test() {
	# leaks_test needs pympler and measures process RSS, which is noise
	# under the sandbox.
	epytest --ignore tests/leaks_test.py
}
