# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="A powerful knowledge base on top of a local folder of plain text Markdown files"
HOMEPAGE="https://obsidian.md/"
SRC_URI="https://github.com/obsidianmd/obsidian-releases/releases/download/v${PV}/${PN}-${PV}.tar.gz"

S="${WORKDIR}/${PN}-${PV}"

LICENSE="Obsidian-EULA"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="appindicator wayland"

RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
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
	x11-libs/libXrandr
	x11-libs/pango
	x11-misc/xdg-utils
	appindicator? ( dev-libs/libayatana-appindicator )
"

src_install() {
	dodir /opt/Obsidian
	cp -r "${S}/." "${ED}/opt/Obsidian/" || die

	fperms +x /opt/Obsidian/obsidian
	if [[ -f "${ED}/opt/Obsidian/chrome-sandbox" ]]; then
		fperms 4711 /opt/Obsidian/chrome-sandbox
	fi

	# Icon
	if [[ -f "${S}/resources/app.asar.unpacked/icon.png" ]]; then
		newicon -s 256 "${S}/resources/app.asar.unpacked/icon.png" obsidian.png
	fi

	# Standard launcher (XWayland under Wayland sessions)
	cat > "${T}/obsidian.desktop" <<-EOF || die
		[Desktop Entry]
		Name=Obsidian
		Exec=/opt/Obsidian/obsidian %u
		Terminal=false
		Type=Application
		Icon=obsidian
		StartupWMClass=obsidian
		Comment=Knowledge base on top of plain text Markdown files
		MimeType=x-scheme-handler/obsidian;
		Categories=Office;
	EOF
	domenu "${T}/obsidian.desktop"

	if use wayland; then
		# Native Wayland launcher (some users report instability)
		cat > "${T}/obsidian-wayland.desktop" <<-EOF || die
			[Desktop Entry]
			Name=Obsidian (Wayland)
			Exec=/opt/Obsidian/obsidian --ozone-platform-hint=auto --enable-features=UseOzonePlatform,WaylandWindowDecorations --enable-wayland-ime %u
			Terminal=false
			Type=Application
			Icon=obsidian
			StartupWMClass=obsidian
			Comment=Knowledge base on top of plain text Markdown files (native Wayland)
			MimeType=x-scheme-handler/obsidian;
			Categories=Office;
		EOF
		domenu "${T}/obsidian-wayland.desktop"
	fi

	dosym -r /opt/Obsidian/obsidian /usr/bin/obsidian
}
