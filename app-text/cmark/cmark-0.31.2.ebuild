# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{10..15} )

inherit cmake python-any-r1

DESCRIPTION="CommonMark parsing and rendering library and program in C"
HOMEPAGE="https://github.com/commonmark/cmark"
SRC_URI="https://github.com/commonmark/cmark/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="BSD-2"
SLOT="0/0.31.2"
KEYWORDS="amd64 ~arm arm64 ~loong ppc ppc64 ~riscv x86"
IUSE="test"
RESTRICT="!test? ( test )"

BDEPEND="test? ( ${PYTHON_DEPS} )"

PATCHES=(
	"${FILESDIR}/cmark-0.31.2_python-3.14.patch"
)

pkg_setup() {
	use test && python-any-r1_pkg_setup
}

src_configure() {
	local mycmakeargs=(
		-DCMARK_LIB_FUZZER=OFF
		-DBUILD_SHARED_LIBS=ON
		-DBUILD_TESTING="$(usex test)"
	)
	cmake_src_configure
}
