# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Check 'next' branch for backports.

inherit autotools flag-o-matic multilib-minimal

MY_PV="${PV/_/-}"
MY_P="${PN}-${MY_PV}"

DESCRIPTION="Protocol Buffers implementation in C"
HOMEPAGE="https://github.com/protobuf-c/protobuf-c"
SRC_URI="
	https://github.com/${PN}/${PN}/releases/download/v${MY_PV}/${MY_P}.tar.gz
"
S="${WORKDIR}/${MY_P}"

LICENSE="BSD-2"
# Subslot == SONAME version
SLOT="0/1.0.0"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~mips ppc ppc64 ~riscv ~s390 ~sparc x86"
IUSE="static-libs"

BDEPEND="
	>=dev-libs/protobuf-3:0
	virtual/pkgconfig
"
# abseil-cpp headers are pulled in transitively by protobuf's
# command_line_interface.h at configure/build time (protobuf >= 22 / abseil).
# The := subslot operator triggers a rebuild when abseil-cpp changes ABI.
DEPEND="
	>=dev-libs/protobuf-3:0=[${MULTILIB_USEDEP}]
	dev-cpp/abseil-cpp:=[${MULTILIB_USEDEP}]
"
RDEPEND="${DEPEND}"

src_prepare() {
	default
	eautoreconf
}

multilib_src_configure() {
	# abseil-cpp >= 20240722 mandates C++20 (std::weak_ordering in <compare>).
	# protobuf compiler header pulled in by configure check trips on gcc-16's
	# default gnu++17. Force gnu++20 so both the configure probe and the build link.
	append-cxxflags -std=gnu++20

	local myeconfargs=(
		$(use_enable static-libs static)
		--enable-year2038
	)

	ECONF_SOURCE="${S}" econf "${myeconfargs[@]}"
}

multilib_src_install_all() {
	find "${ED}" -name '*.la' -type f -delete || die
	einstalldocs
}
