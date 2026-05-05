# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

DESCRIPTION="Bisq 2 — decentralized bitcoin exchange (multi-protocol successor)"
HOMEPAGE="https://bisq.network/ https://github.com/bisq-network/bisq2/"
SRC_URI="https://github.com/bisq-network/bisq2/releases/download/v${PV}/Bisq-${PV}.deb"

S="${WORKDIR}"
LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="-* ~amd64"

RESTRICT="bindist mirror strip"

RDEPEND="
	>=virtual/jre-21:*
	media-libs/alsa-lib
	net-vpn/tor
	x11-libs/libX11
	x11-libs/libXext
	x11-libs/libXi
	x11-libs/libXrender
	x11-libs/libXtst
	x11-misc/xdg-utils"

DEPEND="${RDEPEND}"

QA_PREBUILT="*"
QA_FLAGS_IGNORED="*"

src_prepare() {
	default

	# Remove unnecessary demo files to reduce package size
	if [[ -d opt/bisq2/lib/runtime/demo ]]; then
		rm -rf opt/bisq2/lib/runtime/demo || die "Failed to remove demo files"
	fi
}

src_compile() {
	:
}

src_install() {
	# Verify expected directory structure
	if [[ ! -d "${S}/opt/bisq2" ]]; then
		die "Expected directory structure not found. Package format may have changed."
	fi

	# Copy all files to destination
	dodir /opt/bisq2
	cp -r "${S}"/opt/bisq2/* "${ED}"/opt/bisq2/ || die "Failed to copy bisq2 files"

	# Verify and set permissions for main binary
	if [[ ! -f "${ED}/opt/bisq2/bin/Bisq2" ]]; then
		die "Bisq2 binary not found at expected location"
	fi
	fperms 755 /opt/bisq2/bin/Bisq2

	# Create standard symlink
	dosym ../../opt/bisq2/bin/Bisq2 /usr/bin/bisq2

	# Handle desktop integration
	if [[ -f "${ED}/opt/bisq2/lib/bisq2-Bisq2.desktop" ]]; then
		sed -i \
			-e "s|/opt/bisq2/bin/Bisq2|bisq2|g" \
			-e "s|/opt/bisq2/lib/Bisq2.png|Bisq2|g" \
			"${ED}/opt/bisq2/lib/bisq2-Bisq2.desktop" || die "Failed to fix desktop file"

		domenu "${ED}/opt/bisq2/lib/bisq2-Bisq2.desktop"
	else
		make_desktop_entry bisq2 "Bisq 2 Bitcoin Exchange" Bisq2 "Office;Finance;P2P"
	fi

	# Install icon
	if [[ -f "${ED}/opt/bisq2/lib/Bisq2.png" ]]; then
		doicon "${ED}/opt/bisq2/lib/Bisq2.png"
	fi

	# Optimized wrapper script with G1GC tuning
	cat > "${T}/bisq2-wrapper" <<-EOF || die
		#!/bin/bash
		cd /opt/bisq2 || exit 1
		export JAVA_OPTS="\${JAVA_OPTS} -Xmx2048m -XX:+UseG1GC"
		exec ./bin/Bisq2 "\$@"
	EOF

	exeinto /opt/bisq2
	doexe "${T}/bisq2-wrapper"
	dosym ../../opt/bisq2/bisq2-wrapper /usr/bin/bisq2-wrapper

	# Install copyright if present
	if [[ -f "${S}/opt/bisq2/share/doc/copyright" ]]; then
		dodoc "${S}/opt/bisq2/share/doc/copyright"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Bisq 2 has been installed to /opt/bisq2"
	elog ""
	elog "Launch commands:"
	elog "  bisq2          - Standard launcher"
	elog "  bisq2-wrapper  - Enhanced launcher with Java optimizations"
	elog ""
	elog "Notes:"
	elog "- Java 21 runtime is bundled (located in /opt/bisq2/lib/runtime/)"
	elog "- Configuration stored in: ~/.local/share/Bisq2"
	elog "- Tor is required for P2P networking (net-vpn/tor)"
	elog "- Bisq 2 supports multiple trade protocols (Bisq Easy, MuSig, Submarine)"
	elog "- Bisq 2 coexists with Bisq 1 (net-p2p/bisq-bin) — separate data dirs"
	elog ""
	elog "Report bugs to: https://github.com/bisq-network/bisq2/issues"
}

pkg_postrm() {
	xdg_pkg_postrm
}
