# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# OVERLAY NOTE -- mirrored from ::gentoo's lz4-1.10.0-r1 only because ::gentoo
# has not packaged 1.11.0 yet (released 2026-11-04: multithreaded compression
# in liblz4 via LZ4F_preferences_t.nbWorkers).  Drop this copy once ::gentoo
# ships 1.11.0.
#
# Differences from the ::gentoo 1.10.0-r1 ebuild:
#  - Both ::gentoo patches dropped, both merged upstream: the freestanding
#    test fix (force_align_arg_pointer + -fno-stack-protector) and
#    meson-do-not-force-c99-mode (applies in reverse).
#  - KEYWORDS are all ~arch: this version has not been exercised in bentoo yet.
#
# ABI: upstream states 1.11.0 is binary compatible with 1.10.0 and the meson
# build keeps SONAME liblz4.so.1, so the subslot is deliberately left at
# 1.10.0-meson -- changing it would force a rebuild of every consumer for no
# ABI reason.  The shared library now links threads (shared-multithread
# defaults to true); the static one does not (static-multithread = false).

inherit dot-a meson-multilib

DESCRIPTION="Extremely Fast Compression algorithm"
HOMEPAGE="https://github.com/lz4/lz4"
SRC_URI="https://github.com/lz4/lz4/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="BSD-2 GPL-2"
SLOT="0/1.10.0-meson"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86 ~arm64-macos ~x64-macos ~x64-solaris"
IUSE="static-libs test"
RESTRICT="!test? ( test )"

EMESON_SOURCE=${S}/build/meson

src_configure() {
	use static-libs && lto-guarantee-fat
	multilib-minimal_src_configure
}

multilib_src_configure() {
	local emesonargs=(
		-Dtests=$(usex test true false)
		-Ddefault_library=$(usex static-libs both shared)
		# https://bugs.gentoo.org/940641
		-Dossfuzz=false
	)
	# with -Dprograms=false, the test suite is only rudimentary,
	# so build them for testing non-native ABI as well
	if multilib_is_native_abi || use test; then
		emesonargs+=(
			-Dprograms=true
		)
	fi

	meson_src_configure
}

multilib_src_install_all() {
	einstalldocs
	strip-lto-bytecode
}
