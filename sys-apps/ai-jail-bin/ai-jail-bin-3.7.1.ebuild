# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop

DESCRIPTION="Sandbox for AI coding agents, built on bwrap (upstream prebuilt binary)"
HOMEPAGE="https://github.com/akitaonrails/ai-jail"

# Upstream publishes exactly two release assets: linux-x86_64 and
# macos-aarch64.  There is no Linux aarch64 build, hence KEYWORDS below.
#
# The chromium launcher pair lives in the git tree (dist/desktop/), not in the
# release tarball, so it is fetched from raw.githubusercontent.com pinned to the
# same tag.  Both are plain files, not archives -- see src_unpack().
SRC_URI="
	https://github.com/akitaonrails/ai-jail/releases/download/v${PV}/ai-jail-linux-x86_64.tar.gz
		-> ${P}-amd64.tar.gz
	chromium-launcher? (
		https://raw.githubusercontent.com/akitaonrails/ai-jail/v${PV}/dist/desktop/ai-jail-chromium
			-> ${P}-chromium-launcher.sh
		https://raw.githubusercontent.com/akitaonrails/ai-jail/v${PV}/dist/desktop/ai-jail-chromium.desktop
			-> ${P}-chromium-launcher.desktop
	)
"
# The tarball holds a single top-level file (the ai-jail executable), with no
# containing directory.
S="${WORKDIR}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="chromium-launcher"

# GPL-3 grants redistribution of both source and binary form, so neither
# bindist nor mirror is warranted here; only stripping is restricted, because
# upstream's Cargo release profile already sets strip = true and a prebuilt we
# cannot rebuild must not be rewritten by portage.
RESTRICT="strip"

QA_PREBUILT="usr/bin/ai-jail"

# Verified with `file`, `ldd` and `scanelf -n` on the 1.20.2 x86_64 asset: a PIE
# ELF x86-64, dynamically linked, DT_NEEDED = libgcc_s.so.1, libc.so.6, and the
# highest versioned glibc symbol it references is GLIBC_2.34.  libc itself is
# implicit in every profile, so only gcc (libgcc_s) is named.  Note this is a
# glibc-linked binary and cannot work against musl; ::gentoo handles that class
# of package with a musl profile mask rather than an RDEPEND on sys-libs/glibc,
# which would be unsolvable on musl profiles.
#
# bwrap is not dlopened -- ai-jail execs it as the sandbox itself, so the
# package is inert without it.
#
# The block is weak and declared only here, following this overlay's own
# precedent in sys-apps/uutils-coreutils-bin.  Both packages install
# /usr/bin/ai-jail, so they cannot coexist -- but nothing in the tree RDEPENDs
# on ai-jail, so portage can order the swap itself rather than stopping to make
# the user emerge -C by hand.  A strong "!!" buys nothing here and costs that.
#
# The launcher script execs `ai-jail --browser=soft chromium`, i.e. it needs a
# binary literally named "chromium" on PATH; google-chrome installs
# google-chrome-stable and would not satisfy it.
RDEPEND="
	!sys-apps/ai-jail
	sys-apps/bubblewrap
	sys-devel/gcc:*
	chromium-launcher? ( www-client/chromium )
"

src_unpack() {
	# With USE=chromium-launcher, ${A} also carries the two launcher files,
	# which are a shell script and a desktop entry -- unpack() would fail on
	# them.  Only the tarball is unpacked; the pair is copied into ${S} so the
	# launcher can be patched in src_prepare like any other source file.
	unpack "${P}-amd64.tar.gz"

	if use chromium-launcher; then
		cp "${DISTDIR}/${P}-chromium-launcher.sh" "${S}"/ai-jail-chromium || die
		cp "${DISTDIR}/${P}-chromium-launcher.desktop" \
			"${S}"/ai-jail-chromium.desktop || die
	fi
}

src_prepare() {
	# Upstream's launcher runs `ai-jail --browser=soft chromium` and nothing
	# else, leaving the sandbox with an unshared network namespace and no
	# display socket -- a browser that can neither open a window nor load a
	# page.  The patch grants both and picks --display or --x11 from the session
	# in use.  Only fetched, so only patched, when the flag is on.  Named
	# without a version because the autoupdate applier renames ebuilds, never
	# files/.
	if use chromium-launcher; then
		PATCHES=( "${FILESDIR}"/${PN}-chromium-launcher-caps.patch )
	fi

	default
}

src_install() {
	dobin ai-jail

	# The release tarball contains the executable and nothing else: no README,
	# no LICENSE, so there is nothing to dodoc without pulling an extra
	# distfile just for documentation.

	if use chromium-launcher; then
		dobin ai-jail-chromium
		domenu ai-jail-chromium.desktop
	fi
}
