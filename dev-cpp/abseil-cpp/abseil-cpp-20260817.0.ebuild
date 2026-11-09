# Copyright 2020-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 20260107.1 ebuild, bumped to 20260817.0; python3_15 added.
# The 20260107.0-c++23 patch (abseil-cpp#1992) is part of 20260817.0 and was dropped.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: SRC_URI - the c++23 patch is part of 20260817.0.
# BENTOO-DIVERGENCE: PATCHES - the c++23 patch is part of 20260817.0.
# BENTOO-DIVERGENCE: SLOT - the subslot is computed from PV (2608.0.0 here,
# 2601.1.0 in ::gentoo); the formula is ::gentoo's, only the version moved.
PYTHON_COMPAT=( python3_{10..15} )

inherit cmake-multilib edo flag-o-matic python-any-r1

DESCRIPTION="Abseil Common Libraries (C++), LTS Branch"
HOMEPAGE="https://abseil.io/"
SRC_URI="https://github.com/abseil/abseil-cpp/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"

# ABI, we want rebuilds to avoid hidden breakage
SLOT="0/${PV:2:4}.$(ver_cut 2).0-cpp20"
# SONAME
# SLOT="0/${PV:2:4}.0.0-cpp20"

KEYWORDS="~amd64"
IUSE="debug test test-helpers"

RDEPEND="
	test? (
		dev-cpp/gtest:=[${MULTILIB_USEDEP}]
	)
	test-helpers? (
		dev-cpp/gtest:=[${MULTILIB_USEDEP}]
	)
"
DEPEND="${RDEPEND}"
BDEPEND="
	${PYTHON_DEPS}
	test? (
		sys-libs/timezone-data
	)
"

RESTRICT="!test? ( test )"

PATCHES=(
	"${FILESDIR}/${PN}-20230802.0-sdata-tests.patch"
	"${FILESDIR}/${PN}-20240722.0-lto-odr.patch"
)

src_prepare() {
	cmake_src_prepare

	use ppc && eapply "${FILESDIR}/${PN}-atomic.patch"

	# un-hardcode abseil compiler flags
	# 942192
	sed -i \
		-e '/NOMINMAX/d' \
		absl/copts/copts.py || die

	# now generate cmake files
	python_fix_shebang absl/copts/generate_copts.py
	edo absl/copts/generate_copts.py
}

multilib_src_configure() {
	append-cxxflags "$(usex debug '-DDEBUG' '-DNDEBUG')"

	if [[ ${ABI} == x86 ]]; then
		# error: ‘_mm_cvtsi128_si64’ was not declared in this scope
		# maybe fixed in 4bd9ee20
		local _CXXFLAGS="${CXXFLAGS}"
		local CXXFLAGS="${_CXXFLAGS} -mno-aes"
	fi

	local mycmakeargs=(
		-DCMAKE_CXX_STANDARD=20
		-DABSL_ENABLE_INSTALL="yes"
		-DABSL_USE_EXTERNAL_GOOGLETEST="yes"
		-DABSL_PROPAGATE_CXX_STD="yes"

		# TEST_HELPERS needed for protobuf (bug #915902)
		-DABSL_BUILD_TEST_HELPERS="$(usex test-helpers)"

		-DABSL_BUILD_TESTING="$(usex test)"
	)
	# intentional use, it requires both variables for tests.
	# (BUILD_TESTING AND ABSL_BUILD_TESTING)
	if use test; then
		mycmakeargs+=(
			-DBUILD_TESTING="yes"
		)
	fi

	cmake_src_configure
}

multilib_src_test() {
	if ! use amd64; then
		CMAKE_SKIP_TESTS=(
			absl_symbolize_test
		)

		if use ppc; then
			CMAKE_SKIP_TESTS+=(
				absl_failure_signal_handler_test
			)
		fi
	else
		if ! multilib_is_native_abi; then
			CMAKE_SKIP_TESTS+=(
				absl_hash_instantiated_test
			)
		fi
	fi

	cmake_src_test
}
