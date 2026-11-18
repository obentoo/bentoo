# Copyright 2020-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 0.14.0 ebuild, bumped ahead of ::gentoo to 0.15.0; python3_15
# added. No other change. Drop this copy once ::gentoo ships >=0.15.0 with python3_15.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT.
PYTHON_COMPAT=( python3_{12..15} )
inherit python-any-r1 cmake

DESCRIPTION="CBOR protocol implementation for C and others"
HOMEPAGE="https://github.com/pjk/libcbor"
SRC_URI="https://github.com/PJK/${PN}/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0/$(ver_cut 1-2)"
KEYWORDS="~amd64"
IUSE="doc test"
RESTRICT="!test? ( test )"

BDEPEND="
	doc? (
		$(python_gen_any_dep '
			dev-python/sphinx[${PYTHON_USEDEP}]
			dev-python/sphinx-rtd-theme[${PYTHON_USEDEP}]
			dev-python/breathe[${PYTHON_USEDEP}]
		')
	)
	test? ( dev-util/cmocka )
"

python_check_deps() {
	python_has_version \
		"dev-python/sphinx[${PYTHON_USEDEP}]" \
		"dev-python/sphinx-rtd-theme[${PYTHON_USEDEP}]" \
		"dev-python/breathe[${PYTHON_USEDEP}]"
}

pkg_setup() {
	use doc && python-any-r1_pkg_setup
}

src_configure() {
	local mycmakeargs=(
		-DCMAKE_BUILD_TYPE=Release
		# Set this to avoid automagic until bug #927157 is done
		-DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
		-DWITH_TESTS=$(usex test)
		-Wno-dev
	)

	cmake_src_configure
}

src_compile() {
	cmake_src_compile

	if use doc; then
		mkdir -p doc/build || die
		emake -C doc -j1 html man
	fi
}

src_install() {
	cmake_src_install

	if use doc; then
		dodoc -r "${S}"/doc/build/html
		doman "${S}"/doc/build/man/*.?
	fi
}
