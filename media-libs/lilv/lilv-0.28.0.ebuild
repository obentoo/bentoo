# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's lilv-0.24.26-r1 ebuild, bumped to 0.28.0; python3_15 added.
# Fold back into ::gentoo once it ships >=0.28.0 with python3_15.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT; sord floor raised to 0.16.20 (upstream meson.build).
PYTHON_COMPAT=( python3_{11..15} python3_13t )
PYTHON_REQ_USE='threads(+)'

inherit meson-multilib python-single-r1

DESCRIPTION="Library to make the use of LV2 plugins as simple as possible for applications"
HOMEPAGE="https://drobilla.net/software/lilv.html"
SRC_URI="https://download.drobilla.net/${P}.tar.xz"

LICENSE="ISC"
SLOT="0"
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
KEYWORDS="~amd64"
IUSE="doc python test tools"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"
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
	python? ( ${PYTHON_DEPS} )
	>=dev-libs/serd-0.30.10[${MULTILIB_USEDEP}]
	>=dev-libs/sord-0.16.20[${MULTILIB_USEDEP}]
	>=dev-libs/zix-0.6.0[${MULTILIB_USEDEP}]
	media-libs/libsndfile
	>=media-libs/lv2-1.18.2[${MULTILIB_USEDEP}]
	>=media-libs/sratom-0.6.10[${MULTILIB_USEDEP}]
"
DEPEND="${RDEPEND}"

pkg_setup() {
	use python && python-single-r1_pkg_setup
}

src_prepare() {
	default

	# fix doc installation path
	sed -iE "s/versioned_name/'${PF}'/g" doc/html/meson.build doc/singlehtml/meson.build || die
}

multilib_src_configure() {
	local emesonargs=(
		$(meson_native_use_feature doc docs)
		$(meson_feature python bindings_py)
		$(meson_feature test tests)
		$(meson_feature tools)
	)

	meson_src_configure
}

multilib_src_install() {
	meson_src_install
	use python && python_optimize
}

multilib_src_install_all() {
	local DOCS=( AUTHORS NEWS README.md )
	einstalldocs

	newenvd - 60lv2 <<-EOF
		LV2_PATH=${EPREFIX}/usr/$(get_libdir)/lv2
	EOF
}
