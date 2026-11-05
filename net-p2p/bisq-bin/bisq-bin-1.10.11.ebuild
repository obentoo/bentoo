# Copyright 2019-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

DESCRIPTION="The decentralized bitcoin exchange (non-atomic, with arbitration)"
HOMEPAGE="https://bisq.network/ https://github.com/bisq-network/exchange/"
SRC_URI="https://bisq.network/downloads/v${PV}/Bisq-64bit-${PV}.deb"

S="${WORKDIR}"
LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="~amd64"

RESTRICT="bindist mirror strip"

# Runtime deps reflect what the bundled JDK actually links against
# (libawt_xawt.so → libX11/Xext/Xi/Xrender/Xtst; libjsound.so → libasound).
# JRE of the system is NOT used: bin/Bisq is a jpackage native launcher
# that uses the embedded runtime in /opt/bisq/lib/runtime/.
RDEPEND="
	media-libs/alsa-lib
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
	if [[ -d opt/bisq/lib/runtime/demo ]]; then
		rm -rf opt/bisq/lib/runtime/demo || die "Failed to remove demo files"
	fi

	# Remove non-English man pages to reduce size (optional)
	if [[ -d opt/bisq/lib/runtime/man/ja ]]; then
		rm -rf opt/bisq/lib/runtime/man/ja* || die "Failed to remove Japanese man pages"
	fi
}

src_compile() {
	:
}

src_install() {
	# Verify expected directory structure
	if [[ ! -d "${S}/opt/bisq" ]]; then
		die "Expected directory structure not found. Package format may have changed."
	fi

	# Copy all files to destination
	dodir /opt/bisq
	cp -r "${S}"/opt/bisq/* "${ED}"/opt/bisq/ || die "Failed to copy bisq files"

	# Verify and set permissions for main binary
	if [[ ! -f "${ED}/opt/bisq/bin/Bisq" ]]; then
		die "Bisq binary not found at expected location"
	fi
	fperms 755 /opt/bisq/bin/Bisq

	# Create standard symlink
	dosym ../../opt/bisq/bin/Bisq /usr/bin/bisq

	# Handle desktop integration
	if [[ -f "${ED}/opt/bisq/lib/bisq-Bisq.desktop" ]]; then
		# Fix desktop file paths and validation
		sed -i \
			-e "s|/opt/bisq/bin/Bisq|bisq|g" \
			-e "s|/opt/bisq/lib/Bisq.png|Bisq|g" \
			"${ED}/opt/bisq/lib/bisq-Bisq.desktop" || die "Failed to fix desktop file"

		domenu "${ED}/opt/bisq/lib/bisq-Bisq.desktop"
	else
		# Create fallback desktop entry
		make_desktop_entry bisq "Bisq Bitcoin Exchange" Bisq "Office;Finance;P2P"
	fi

	# Install icon
	if [[ -f "${ED}/opt/bisq/lib/Bisq.png" ]]; then
		doicon "${ED}/opt/bisq/lib/Bisq.png"
	fi

	# Create optimized wrapper script.
	# bin/Bisq is a jpackage native launcher (ELF), not a shell/java script.
	# It ignores JAVA_OPTS — JVM tuning must be passed as -J<opt> arguments.
	cat > "${T}/bisq-wrapper" <<-EOF || die
		#!/bin/bash
		exec /opt/bisq/bin/Bisq -J-Xmx2048m -J-XX:+UseG1GC "\$@"
	EOF

	exeinto /opt/bisq
	doexe "${T}/bisq-wrapper"
	dosym ../../opt/bisq/bisq-wrapper /usr/bin/bisq-wrapper

	# Handle copyright file
	if [[ -f "${S}/opt/bisq/share/doc/copyright" ]]; then
		dodoc "${S}/opt/bisq/share/doc/copyright"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Bisq Bitcoin Exchange has been installed to /opt/bisq"
	elog ""
	elog "Launch commands:"
	elog "  bisq              - Standard launcher"
	elog "  bisq-wrapper      - Enhanced launcher with Java optimizations"
	elog ""
	elog "Important notes:"
	elog "- Java 11+ runtime is bundled (located in /opt/bisq/lib/runtime/)"
	elog "- Configuration stored in: ~/.local/share/Bisq"
	elog "- Initial blockchain sync requires ~10GB+ disk space"
	elog "- Network connectivity required (P2P and Tor)"
	elog "- Some ISPs may block P2P traffic"
	elog ""
	elog "For troubleshooting Java issues, use: bisq-wrapper"
	elog "Report bugs to: https://github.com/bisq-network/bisq/issues"
}

pkg_postrm() {
	xdg_pkg_postrm
}
