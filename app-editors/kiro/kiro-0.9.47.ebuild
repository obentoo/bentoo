# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit bash-completion-r1 desktop xdg

DESCRIPTION="AI IDE that helps you do your best work by turning ideas into production code"
HOMEPAGE="https://kiro.dev/"
SRC_URI="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/signed/${PV}/tar/${PN}-ide-${PV}-stable-linux-x64.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="wayland"

RESTRICT="mirror strip bindist"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.5.3
	app-crypt/libsecret
	>=dev-libs/expat-2.1_beta3
	>=dev-libs/glib-2.37.3:2
	>=dev-libs/nspr-4.9
	>=dev-libs/nss-3.26
	>=media-libs/alsa-lib-1.0.17
	>=media-libs/mesa-17.1.0[gbm(+)]
	>=net-misc/curl-7.0.0
	>=net-print/cups-1.6.0
	>=sys-apps/dbus-1.9.14
	>=sys-apps/util-linux-2.25
	>=x11-libs/cairo-1.6.0
	>=x11-libs/gtk+-3.9.10:3[wayland?]
	>=x11-libs/libdrm-2.4.75
	>=x11-libs/libX11-1.4.99.1
	>=x11-libs/libxcb-1.9.2
	>=x11-libs/libXcomposite-0.4.4
	>=x11-libs/libXdamage-1.1
	x11-libs/libXext
	x11-libs/libXfixes
	>=x11-libs/libxkbcommon-0.5.0
	>=x11-libs/libxkbfile-1.1.0
	x11-libs/libXrandr
	>=x11-libs/pango-1.14.0
	>=x11-misc/xdg-utils-1.0.2
	wayland? ( dev-libs/wayland )
	media-libs/vulkan-loader
"

QA_PREBUILT="
	opt/kiro/kiro
	opt/kiro/chrome_crashpad_handler
	opt/kiro/chrome-sandbox
	opt/kiro/lib*.so*
"

# tar extracts to Kiro/ subdirectory
S="${WORKDIR}/Kiro"

src_prepare() {
	default

	# Set chrome-sandbox SUID permissions before install
	chmod 4755 chrome-sandbox || die "Failed to set chrome-sandbox permissions"

	# Verify main binary exists
	[[ -f kiro ]] || die "Main Kiro executable not found!"
}

src_install() {
	# Install all application files to /opt/kiro
	insinto /opt/kiro
	doins -r .

	# Fix permissions: main executables
	fperms +x /opt/kiro/kiro
	fperms +x /opt/kiro/chrome_crashpad_handler
	fperms 4755 /opt/kiro/chrome-sandbox
	fperms +x /opt/kiro/bin/kiro

	# Fix permissions: shared libraries
	while IFS= read -r -d '' lib; do
		fperms +x "${lib#${D}}"
	done < <(find "${D}/opt/kiro" -name "*.so*" -type f -print0)

	# Symlink wrapper to /usr/bin — bin/kiro uses readlink -f to resolve /opt/kiro correctly
	dosym /opt/kiro/bin/kiro /usr/bin/kiro

	# Icon — 1024x1024 PNG installed at standard hicolor sizes
	local icon="resources/app/resources/linux/code.png"
	for size in 16 32 48 64 128 256 512; do
		newicon -s ${size} "${icon}" kiro.png
	done

	# Main desktop entry
	cat > "${T}/kiro.desktop" <<-EOF
		[Desktop Entry]
		Version=1.0
		Type=Application
		Name=Kiro IDE
		Comment=AI IDE that helps you do your best work by turning ideas into production code
		Exec=/opt/kiro/kiro %F
		Icon=kiro
		Categories=Development;IDE;TextEditor;
		MimeType=text/plain;inode/directory;
		StartupWMClass=kiro
		StartupNotify=true
		Terminal=false
		Keywords=kiro;
		GenericName=Text Editor
	EOF
	domenu "${T}/kiro.desktop"

	# URL handler desktop entry
	cat > "${T}/kiro-url-handler.desktop" <<-EOF
		[Desktop Entry]
		Version=1.0
		Type=Application
		Name=Kiro IDE URL Handler
		Comment=Handle Kiro IDE URLs
		Exec=/opt/kiro/kiro --open-url %U
		Icon=kiro
		Categories=Development;IDE;
		NoDisplay=true
		StartupNotify=true
		Terminal=false
		MimeType=x-scheme-handler/kiro;
	EOF
	domenu "${T}/kiro-url-handler.desktop"

	# Shell completions
	dobashcomp resources/completions/bash/kiro

	insinto /usr/share/zsh/site-functions
	doins resources/completions/zsh/_kiro
}

pkg_postinst() {
	xdg_pkg_postinst

	if [[ ! -x "${EROOT}/opt/kiro/kiro" ]]; then
		eerror "Kiro executable was not installed correctly!"
		die "Installation verification failed"
	fi

	elog "Kiro IDE ${PV} successfully installed."
	elog "  Executable : ${EROOT}/opt/kiro/kiro"
	elog "  Wrapper    : ${EROOT}/usr/bin/kiro"
	elog "  Config     : ~/.config/kiro/"
	elog "  Docs       : https://kiro.dev/"
}

pkg_postrm() {
	xdg_pkg_postrm
}
