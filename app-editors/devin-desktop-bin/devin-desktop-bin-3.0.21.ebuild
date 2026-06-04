# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop shell-completion unpacker xdg

MY_PN="devin-desktop"

DESCRIPTION="AI-powered code editor (formerly Windsurf) keeping you in flow state"
HOMEPAGE="https://devin.ai"

SRC_URI="https://windsurf-stable.codeiumdata.com/wVxQEIWkwPUEAGf3/apt/pool/main/d/${MY_PN}/Devin-linux-x64-${PV}.deb"
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
	# Upstream rebranded Windsurf -> Devin Desktop as of 3.x: the .deb ships all
	# artifacts under "devin-desktop" (binary, desktop files, icon, etc.).
	mkdir -p "${ED}/opt/${MY_PN}" || die
	cp -r "${S}/usr/share/${MY_PN}/"* "${ED}/opt/${MY_PN}" || die

	# Fix chrome-sandbox permissions
	fperms 4755 "/opt/${MY_PN}/chrome-sandbox"

	# Install launcher symlink (upstream binary is "devin-desktop")
	dosym "../../opt/${MY_PN}/${MY_PN}" "/usr/bin/${MY_PN}"

	# Fix paths in desktop files
	sed -i \
		-e "s|/usr/share/${MY_PN}/${MY_PN}|/opt/${MY_PN}/${MY_PN}|g" \
		"${S}/usr/share/applications/${MY_PN}.desktop" \
		"${S}/usr/share/applications/${MY_PN}-url-handler.desktop" \
		|| die "sed failed"

	# Install desktop files
	domenu "${S}/usr/share/applications/${MY_PN}.desktop"
	domenu "${S}/usr/share/applications/${MY_PN}-url-handler.desktop"

	# Install icon
	doicon "${S}/usr/share/pixmaps/${MY_PN}.png"

	# Install metainfo
	insinto /usr/share/metainfo
	doins "${S}/usr/share/appdata/${MY_PN}.appdata.xml"

	# Install MIME type definitions
	insinto /usr/share/mime/packages
	doins "${S}/usr/share/mime/packages/${MY_PN}-workspace.xml"

	# Install completions
	dobashcomp "${S}/usr/share/bash-completion/completions/${MY_PN}"
	newzshcomp "${S}/usr/share/zsh/vendor-completions/_${MY_PN}" "_${MY_PN}"
}
