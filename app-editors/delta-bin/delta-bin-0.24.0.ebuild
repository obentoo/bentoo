# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="AI-native code editor from the creators of Zed (binary package)"
HOMEPAGE="https://delta.dev"
SRC_URI="
	https://releases.delta.dev/releases/stable/${PV}/delta-linux-x86_64.tar.gz
		-> ${P}-linux-x86_64.tar.gz
"
S="${WORKDIR}/Delta"

LICENSE="Delta-EAA"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="mirror strip bindist"

# Libraries the binaries dlopen() at runtime, taken from upstream's own
# runtime list in github.com/zed-industries/delta-nix (flake.nix). Only libc,
# libm, libunwind and the bundled xcb/xkbcommon are linked directly.
RDEPEND="
	dev-libs/openssl:0/3
	dev-libs/wayland
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/libglvnd
	media-libs/vulkan-loader
	virtual/zlib
	x11-libs/libX11
	x11-libs/libXcursor
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrandr
	x11-libs/libXrender
	x11-libs/libxcb
	x11-libs/xcb-util
	x11-libs/xcb-util-cursor
	x11-libs/xcb-util-image
	x11-libs/xcb-util-keysyms
	x11-libs/xcb-util-renderutil
	x11-libs/xcb-util-wm
	x11-misc/xkeyboard-config
"

QA_PREBUILT="opt/delta-bin/*"

src_install() {
	# bin/ finds delta-app and lib/ through /proc/self/exe and
	# RPATH=$ORIGIN/../lib, so the tree must stay together.
	insinto /opt/delta-bin
	doins -r bin lib
	fperms 0755 /opt/delta-bin/bin/{delta,delta-app}

	# /usr/bin/delta belongs to dev-util/git-delta, hence the -bin name.
	# DELTA_UPDATE_EXPLANATION makes the in-app updater stand down: /opt is
	# owned by Portage, not by the user running Delta.
	newbin - delta-bin <<-EOF
		#!/bin/sh
		export DELTA_UPDATE_EXPLANATION="Delta is managed by Portage; update app-editors/delta-bin instead."
		exec /opt/delta-bin/bin/delta "\$@"
	EOF

	local icon size
	for icon in share/icons/hicolor/*/apps/dev.zed.Delta.png; do
		size=${icon#share/icons/hicolor/}
		size=${size%%x*}
		doicon -s "${size}" "${icon}"
	done

	sed -e 's|^Exec=delta |Exec=delta-bin |' \
		share/applications/dev.zed.Delta.desktop \
		> "${T}"/dev.zed.Delta.desktop || die
	grep -q '^Exec=delta-bin open %U$' "${T}"/dev.zed.Delta.desktop \
		|| die "upstream .desktop Exec= line changed"
	domenu "${T}"/dev.zed.Delta.desktop
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Launch Delta with: delta-bin"
	elog "The CLI is installed as 'delta-bin' because /usr/bin/delta belongs to"
	elog "dev-util/git-delta. Delta requires a Zed account and is distributed"
	elog "under the Zed Early Access Agreement (LICENSE=Delta-EAA)."
}
