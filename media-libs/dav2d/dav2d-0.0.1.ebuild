# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit git-r3 meson-multilib

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://code.videolan.org/videolan/dav2d"
else
	# No official tarball: downloads.videolan.org has no dav2d release dir
	# and the GitLab archive endpoint is behind Anubis anti-bot (returns HTML).
	# Pin the peeled commit of tag 0.0.1 and fetch via git-r3.
	EGIT_REPO_URI="https://code.videolan.org/videolan/dav2d"
	EGIT_COMMIT="0430370c7f84de6b81839785c5e5411a9d39dcec"
	KEYWORDS="~amd64"
fi

DESCRIPTION="dav2d is an AV2 Decoder :)"
HOMEPAGE="https://code.videolan.org/videolan/dav2d"

LICENSE="BSD-2"
# Check SONAME on version bumps!
SLOT="0/1"
IUSE="+8bit +10bit +asm test xxhash"
RESTRICT="!test? ( test )"

ASM_DEPEND=">=dev-lang/nasm-2.15.05"
DEPEND="xxhash? ( dev-libs/xxhash )"
BDEPEND="
	asm? (
		abi_x86_32? ( ${ASM_DEPEND} )
		abi_x86_64? ( ${ASM_DEPEND} )
	)
"

DOCS=( README.md doc/PATENTS THANKS.md NEWS )

multilib_src_configure() {
	local -a bits=()
	use 8bit  && bits+=( 8 )
	use 10bit && bits+=( 16 )

	local enable_asm
	if [[ ${MULTILIB_ABI_FLAG} == abi_x86_x32 ]]; then
		enable_asm=false
	else
		enable_asm=$(usex asm true false)
	fi

	local emesonargs=(
		-Dbitdepths=$(IFS=,; echo "${bits[*]}")
		-Denable_asm=${enable_asm}
		$(meson_use test enable_tests)
		$(meson_feature xxhash xxhash_muxer)
	)
	meson_src_configure
}

multilib_src_test() {
	if multilib_is_native_abi ; then
		meson_src_test
	fi
}
