# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's sratom-0.6.18-r1 ebuild, bumped to 0.6.22; python3_15 added.
# Fold back into ::gentoo once it ships >=0.6.22 with python3_15.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT.
PYTHON_COMPAT=( python3_{9..15} )
PYTHON_REQ_USE='threads(+)'
inherit meson-multilib python-any-r1

DESCRIPTION="Library for serialising LV2 atoms to/from RDF, particularly the Turtle syntax"
HOMEPAGE="https://drobilla.net/software/sratom.html"
SRC_URI="https://download.drobilla.net/${P}.tar.xz"

LICENSE="ISC"
SLOT="0"
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
KEYWORDS="~amd64"
IUSE="doc test"
RESTRICT="!test? ( test )"

BDEPEND="
	virtual/pkgconfig
	doc? (
		app-text/doxygen
		dev-python/sphinx
		dev-python/sphinx-lv2-theme
		dev-python/sphinxygen
)
"
# Take care on bumps to check minimum versions!
RDEPEND="
	>=dev-libs/serd-0.30.10
	>=dev-libs/sord-0.16.16
	>=media-libs/lv2-1.18.4
"
DEPEND="${RDEPEND}
	${PYTHON_DEPS}
"

src_prepare() {
	default

	# fix doc installation path
	sed -iE "s/versioned_name/'${PF}'/g" doc/html/meson.build doc/singlehtml/meson.build || die
}

multilib_src_configure() {
	local emesonargs=(
		$(meson_native_use_feature doc docs)
		$(meson_feature test tests)
	)

	meson_src_configure
}

multilib_src_install_all() {
	local DOCS=( NEWS README.md )
	einstalldocs
}
