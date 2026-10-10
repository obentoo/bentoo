# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit xdg

# The prebuilt form of app-editors/zeo at the same ${PV}: the same Zed commit and
# the same patch series, compiled for x86-64-v3 by
# zed-patches/scripts/release-portable.sh -- in a Debian 12 container with the
# official Rust toolchain, the build that also makes the .deb, .rpm, AppImage and
# Flatpak. Up to -r1 it was built on a Gentoo host, whose Rust standard library
# targets znver5 and put AVX-512 into the binary; this build refuses any
# compiler-generated AVX-512. PROVENANCE.txt inside the tarball names the commit,
# every patch with its sha256, the toolchains and the flags.
EGIT_COMMIT="089abd691765e6ffdfc09a34a29b6c7bbca18067"

DESCRIPTION="Zeo - the Zed editor, rebranded, with the bentoo patch series (binary)"
HOMEPAGE="https://github.com/zeo-workspace/zeo https://zed.dev"
# The tarball is an asset of the Zeo release tagged v${PVR}, which also carries
# PROVENANCE and SHA256SUMS; until 2026-10-03 it was served from R2, which still
# holds the same bytes under the same name. ${PF}, not ${P}: the name carries
# zeo's revision, because a zeo revbump is a different binary and no host may
# serve new bytes under a name an older Manifest already pins.
SRC_URI="https://github.com/zeo-workspace/zeo/releases/download/v${PVR}/${PF}-amd64.tar.xz"
S="${WORKDIR}/${PF}"

# The Corresponding Source of this binary (GPL-3 section 6) is the Zed tarball
# named by EGIT_COMMIT plus the patches in app-editors/zeo/files/ at this ${PV};
# PROVENANCE.txt carries the exact list.
LICENSE="GPL-3+
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD-2 BSD Boost-1.0
	CC0-1.0 CDLA-Permissive-2.0 ISC LGPL-3 MIT MIT-0 MPL-2.0 UoI-NCSA
	Unicode-3.0 ZLIB BZIP2
"
SLOT="0"
KEYWORDS="-* ~amd64"
# Only the dependency half of these flags is honest on a binary: the
# integration patches are compiled in either way, and these decide whether what
# they talk to is pulled in -- the two ACP adapters, and for claude-code-ide
# (patch 0002) the claude CLI that connects to the IDE server in Zeo-spawned
# terminals.
IUSE="+claude-agent-acp-plus +claude-agent-acp-tui +claude-code-ide"
# Never bindist: redistributing this binary is the reason the package exists.
RESTRICT="mirror strip"

# NEEDED is measured on the shipped binary with scanelf (unchanged since -r2,
# whose libX11-xcb x11-libs/libX11 provides). The dlopen()ed
# libraries are invisible to scanelf and are listed from what gpui loads at run
# time: Vulkan, the Wayland client and libX11.
RDEPEND="
	!app-editors/zed
	!app-editors/zed-bin
	!app-editors/zeo
	media-libs/alsa-lib
	dev-libs/glib:2
	x11-libs/libxcb
	x11-libs/libxkbcommon[X]
	media-libs/vulkan-loader
	dev-libs/wayland
	x11-libs/libX11
	|| (
		media-fonts/dejavu
		media-fonts/cantarell
		media-fonts/noto
		media-fonts/ubuntu-font-family
	)
	claude-agent-acp-plus? ( >=dev-util/claude-agent-acp-plus-0.24.0 )
	claude-agent-acp-tui? ( dev-util/claude-agent-acp-tui )
	claude-code-ide? ( dev-util/claude-code )
"

QA_PREBUILT="
	usr/bin/zeo
	usr/libexec/zeo-editor
"

pkg_pretend() {
	# Compiled for x86-64-v3. On an older CPU the editor dies with SIGILL at the
	# first AVX2 instruction, which reads as a crash rather than as the wrong
	# package; this turns it into a message. Skipped when building for another
	# machine, where this CPU says nothing.
	[[ ${MERGE_TYPE} == buildonly ]] && return
	[[ ${ROOT:-/} != / ]] && return
	local flag missing=()
	for flag in avx2 fma bmi2 movbe; do
		grep -qw "${flag}" /proc/cpuinfo || missing+=( "${flag}" )
	done
	if [[ ${#missing[@]} -gt 0 ]]; then
		eerror "This binary needs an x86-64-v3 CPU (Haswell / Zen 1 or newer)."
		eerror "Missing: ${missing[*]}"
		eerror "Install app-editors/zeo instead, which compiles for this machine."
		die "CPU below x86-64-v3"
	fi
}

src_install() {
	cp -a usr "${ED}"/ || die
	dodoc PROVENANCE.txt
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Zeo (binary) installed. Launch with: zeo"

	if use claude-agent-acp-plus; then
		elog ""
		elog "Claude Agent (Plus) is available in Zeo's agent panel by default and runs"
		elog "the adapter installed as /usr/bin/claude-agent-acp-plus. No settings.json"
		elog "entry is needed."
	fi

	if use claude-agent-acp-tui; then
		elog ""
		elog "Claude Agent TUI is available in Zeo's agent panel by default and runs"
		elog "the bridge installed as /usr/bin/claude-agent-acp-tui. No settings.json"
		elog "entry is needed."
	fi

	if use claude-code-ide; then
		elog ""
		elog "Claude Code IDE integration uses an unofficial, reverse-engineered"
		elog "protocol that may break without notice."
		elog "It activates automatically in Zeo-spawned terminals via environment"
		elog "variables; no settings.json configuration is needed."
		elog "Verify the connection by running /ide inside 'claude'."
	fi
}
