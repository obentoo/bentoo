# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=9

# Copy of ::gentoo's 0.1.15 built against mdds 3 instead of mdds 2.1: this overlay
# ships mdds 3.x/4.x, not 2.1. 0.1.15's own sources handle the mdds 3 API.
# BENTOO-DIVERGENCE: RDEPEND - dev-util/mdds:1/3.0 (::gentoo: >=dev-util/mdds-2.1:1=).
# The subslot is pinned because --with-mdds=3.0 makes configure look for
# mdds-3.0.pc, which mdds 4.0 (SLOT 1/4.0, mdds-4.0.pc) no longer installs.
# BENTOO-DIVERGENCE: ECONF - --with-mdds=3.0 (::gentoo: --with-mdds=2.1).
inherit autotools

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://git.libreoffice.org/libetonyek.git"
	inherit git-r3
else
	SRC_URI="https://dev-www.libreoffice.org/src/libetonyek/${P}.tar.xz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc64 ~riscv ~x86"
fi

DESCRIPTION="Library parsing Apple Keynote presentations"
HOMEPAGE="https://wiki.documentfoundation.org/DLP/Libraries/libetonyek"

LICENSE="|| ( GPL-2+ LGPL-2.1 MPL-1.1 )"
SLOT="0"
IUSE="doc test"
RESTRICT="!test? ( test )"

RDEPEND="
	app-text/liblangtag
	dev-libs/librevenge
	dev-libs/libxml2:=
	dev-util/mdds:1/3.0
	virtual/zlib:=
"
DEPEND="${RDEPEND}
	dev-libs/boost
	media-libs/glm
	dev-build/libtool
	test? ( dev-util/cppunit )
"
BDEPEND="
	virtual/pkgconfig
	doc? ( app-text/doxygen )
"

src_prepare() {
	default
	[[ -d m4 ]] || mkdir "m4" || die
	eautoreconf
}

src_configure() {
	local myeconfargs=(
		--disable-werror
		--with-mdds=3.0
		$(use_with doc docs)
		$(use_enable test tests)
	)
	econf "${myeconfargs[@]}"
}

src_install() {
	default
	find "${ED}" -name '*.la' -type f -delete || die
}
