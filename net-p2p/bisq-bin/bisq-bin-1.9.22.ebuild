# Copyright 2019-2025 Gentoo Authors
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
IUSE=""

RESTRICT="mirror strip"

# Dependencies based on Debian package analysis and Gentoo equivalents
RDEPEND="
	>=virtual/jre-11:*
	x11-libs/gtk+:3
	x11-misc/xdg-utils"

DEPEND="${RDEPEND}"

# QA variables for binary package - comprehensive file listing
QA_PREBUILT="
	opt/bisq/bin/Bisq
	opt/bisq/lib/libapplauncher.so
	opt/bisq/lib/runtime/bin/*
	opt/bisq/lib/runtime/lib/*.so
	opt/bisq/lib/runtime/lib/*/*.so"

# Exclude problematic libraries that may cause QA warnings
QA_FLAGS_IGNORED="
	opt/bisq/bin/Bisq
	opt/bisq/lib/libapplauncher.so
	opt/bisq/lib/runtime/bin/*
	opt/bisq/lib/runtime/lib/*.so"

# Exclude bundled FFmpeg libraries from dependency checks
REQUIRES_EXCLUDE="
	libgstreamer-lite.so
	libavplugin-53.so
	libavplugin-54.so
	libavplugin-55.so
	libavplugin-56.so
	libavplugin-57.so
	libavplugin-ffmpeg-56.so
	libavplugin-ffmpeg-57.so"

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

	# Create optimized wrapper script
	cat > "${T}/bisq-wrapper" <<-EOF || die
		#!/bin/bash
		# Bisq wrapper script for better Java integration
		
		# Set working directory
		cd /opt/bisq || exit 1
		
		# Set Java options for better performance
		export JAVA_OPTS="\${JAVA_OPTS} -Xmx2048m -XX:+UseG1GC"
		
		# Launch Bisq with arguments
		exec ./bin/Bisq "\$@"
	EOF
	
	exeinto /opt/bisq
	doexe "${T}/bisq-wrapper"
	dosym ../../opt/bisq/bisq-wrapper /usr/bin/bisq-wrapper

	# Install documentation if present
	if [[ -d "${S}/opt/bisq/share/doc" ]]; then
		dodoc "${S}"/opt/bisq/share/doc/*
	fi

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