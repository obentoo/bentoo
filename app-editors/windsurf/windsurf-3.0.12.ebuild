# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop shell-completion unpacker xdg

DESCRIPTION="AI-powered code editor maintaining flow state with instant assistance."
HOMEPAGE="https://codeium.com"

SRC_URI="https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt/pool/main/d/devin-desktop/Devin-linux-x64-${PV}.deb"
S="${WORKDIR}"

# License same as vscode
LICENSE="
	Apache-2.0
	BSD
	BSD-1
	BSD-2
	BSD-4
	CC-BY-4.0
	ISC
	LGPL-2.1+
	Microsoft-vscode
	MIT
	MPL-2.0
	openssl
	PYTHON
	TextMate-bundle
	Unlicense
	UoI-NCSA
	W3C
"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="mirror strip bindist"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret[crypt]
	app-crypt/mit-krb5
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa
	net-misc/curl
	sys-apps/dbus
	sys-process/lsof
	virtual/zlib
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libxkbfile
	x11-libs/libXrandr
	x11-libs/libXScrnSaver
	x11-libs/pango
	x11-misc/xdg-utils
"

QA_PREBUILT="*"

src_install() {
	# Upstream rebranded Windsurf -> Devin as of 3.x: the .deb ships all
	# artifacts under "devin-desktop" (binary, desktop files, icon, etc.). The
	# package and the user-facing command remain "windsurf" for continuity.
	mkdir -p "${ED}/opt/${PN}" || die
	cp -r "${S}/usr/share/devin-desktop/"* "${ED}/opt/${PN}" || die

	# Fix chrome-sandbox permissions
	fperms 4755 /opt/windsurf/chrome-sandbox

	# Install launcher script (upstream binary is now "devin-desktop")
	dosym ../../opt/windsurf/devin-desktop /usr/bin/windsurf

	# Fix paths in desktop files
	sed -i \
		-e 's|/usr/share/devin-desktop/devin-desktop|/opt/windsurf/devin-desktop|g' \
		"${S}/usr/share/applications/devin-desktop.desktop" \
		"${S}/usr/share/applications/devin-desktop-url-handler.desktop" \
		|| die "sed failed"

	# Install desktop files
	domenu "${S}/usr/share/applications/devin-desktop.desktop"
	domenu "${S}/usr/share/applications/devin-desktop-url-handler.desktop"

	# Install icon
	doicon "${S}/usr/share/pixmaps/devin-desktop.png"

	# Install metainfo
	insinto /usr/share/metainfo
	doins "${S}/usr/share/appdata/devin-desktop.appdata.xml"

	# Install MIME type definitions
	insinto /usr/share/mime/packages
	doins "${S}/usr/share/mime/packages/devin-desktop-workspace.xml"

	# Install completions
	newbashcomp "${S}/usr/share/bash-completion/completions/devin-desktop" windsurf
	newzshcomp "${S}/usr/share/zsh/vendor-completions/_devin-desktop" _windsurf
}
