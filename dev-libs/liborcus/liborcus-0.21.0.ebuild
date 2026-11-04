# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{11..15} )
# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo carries
# liborcus-0.19.2-boost-m4.patch. Verified 2026-09-07: it reverse-applies
# cleanly against the 0.21.0 tarball, so upstream shipped the same change and
# their copy is a backport onto 0.19.2.
inherit autotools python-single-r1

DESCRIPTION="Standalone file import filter library for spreadsheet documents"
HOMEPAGE="https://gitlab.com/orcus/orcus/blob/master/README.md"

if [[ ${PV} == *9999* ]]; then
	MDDS_SLOT="1/3.0"
	EGIT_REPO_URI="https://gitlab.com/orcus/orcus.git"
	inherit git-r3
else
	MDDS_SLOT="1/3.0"
	# "404s" but serves HTML for 0.20.0
	#SRC_URI="https://kohei.us/files/orcus/src/${P}.tar.xz"
	SRC_URI="https://gitlab.com/api/v4/projects/orcus%2Forcus/packages/generic/source/${PV}/${P}.tar.gz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
fi

LICENSE="MIT"
SLOT="0/0.21" # based on SONAME of liborcus.so
IUSE="python +spreadsheet-model test tools"

REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"
RESTRICT="!test? ( test )"

RDEPEND="
	dev-libs/boost:=[zlib(+)]
	virtual/zlib:=
	python? ( ${PYTHON_DEPS} )
	spreadsheet-model? ( dev-libs/libixion:0/0.20 )
"
DEPEND="
	${RDEPEND}
	dev-util/mdds:${MDDS_SLOT}
"

pkg_setup() {
	use python && python-single-r1_pkg_setup
}

src_prepare() {
	default
	eautoreconf
}

src_configure() {
	local myeconfargs=(
		--without-benchmark
		--disable-werror
		$(use_enable python)
		$(use_enable spreadsheet-model)
		$(use_with tools)
	)
	econf "${myeconfargs[@]}"
}

src_install() {
	default
	use python && python_optimize
	find "${D}" -name '*.la' -type f -delete || die
}
