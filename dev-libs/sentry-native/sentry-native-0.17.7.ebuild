# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo wraps sentry_fuzz_json in
# if(0) via sentry-native-0.6.5_no-fuzz-test.patch. Deliberately not copied, and
# the reason changed once the upstream file was actually read.
#
# ::gentoo's rationale is about RUNNING the fuzzer: their patch drops both the
# target and the add_test that registered it, because sentry_fuzz_json needs a
# special, performance-killing build to work at all. In 0.16.5 that add_test is
# GONE - checked 2026-09-07 in tests/unit/CMakeLists.txt, where the only
# add_test calls are sentry/unit-tests and the per-case sentry/* ones. The
# fuzz target is compiled under USE=test and never executed.
#
# So the patch would buy one fewer compiled target, not a test that stops
# failing, and it does not apply as written either (hunk 2 fails; the file was
# restructured since 0.6.5). Carrying a rebased downstream patch to skip a build
# target is maintenance cost with no correctness behind it.
#
# CORRECTED 2026-09-07: an earlier version of this tag claimed the target was
# "built and registered", which was wrong on the second half and made ::gentoo's
# reason look like it still applied here.
inherit cmake

DESCRIPTION="Sentry SDK for C, C++ and native applications"
HOMEPAGE="https://sentry.io/ https://github.com/getsentry/sentry-native"
SRC_URI="https://github.com/getsentry/${PN}/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+breakpad +curl test"
RESTRICT="!test? ( test )"

RDEPEND="
	breakpad? ( dev-util/breakpad )
	curl? (
		net-misc/curl
		virtual/zlib:=
	)
"
DEPEND="${RDEPEND}"
BDEPEND="virtual/pkgconfig"

src_configure() {
	local mycmakeargs=(
		-DSENTRY_BUILD_EXAMPLES=OFF
		-DSENTRY_BACKEND=$(usex breakpad "breakpad" "inproc")
		-DSENTRY_BUILD_TESTS=$(usex test)
		-DSENTRY_TRANSPORT=$(usex curl "curl" "none")
		-DSENTRY_TRANSPORT_COMPRESSION=$(usex curl)
	)
	# Avoid "not used by the project" warnings when USE=-breakpad
	if use breakpad; then
		mycmakeargs+=( -DSENTRY_BREAKPAD_SYSTEM=ON )
	fi

	cmake_src_configure
}
