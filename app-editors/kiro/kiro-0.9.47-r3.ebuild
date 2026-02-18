# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CHROMIUM_LANGS="af am ar bg bn ca cs da de el en-GB es es-419 et fa fi fil fr gu he
	hi hr hu id it ja kn ko lt lv ml mr ms nb nl pl pt-BR pt-PT ro ru sk sl sr
	sv sw ta te th tr uk ur vi zh-CN zh-TW"

inherit chromium-2 desktop optfeature pax-utils shell-completion xdg

DESCRIPTION="AI IDE that helps you do your best work by turning ideas into production code"
HOMEPAGE="https://kiro.dev/"
SRC_URI="https://prod.download.desktop.kiro.dev/releases/stable/linux-x64/signed/${PV}/tar/${PN}-ide-${PV}-stable-linux-x64.tar.gz -> ${P}.tar.gz"

# Main: AWS proprietary (AWS Customer Agreement + AWS IP License)
# Bundled Chromium/Electron/Node: see LICENSES.chromium.html and ThirdPartyNotices.txt
LICENSE="
	AWS-IP
	Apache-2.0
	Artistic-2
	BSD
	BSD-2
	CC-BY-4.0
	CC0-1.0
	ISC
	LGPL-2.1+
	MIT
	MPL-2.0
	PSF-2
	Unicode-3.0
	Unlicense
	W3C
	ZLIB
	openssl
"
SLOT="0"
KEYWORDS="~amd64"
IUSE="kerberos wayland"

RESTRICT="mirror strip bindist"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret[crypt]
	app-misc/ca-certificates
	>=dev-libs/expat-2.1_beta3
	>=dev-libs/glib-2.37.3:2
	>=dev-libs/nspr-4.9
	>=dev-libs/nss-3.26
	>=media-libs/alsa-lib-1.0.17
	media-libs/libglvnd
	>=media-libs/mesa-17.1.0[gbm(+)]
	>=net-misc/curl-7.0.0
	>=net-print/cups-1.6.0
	>=sys-apps/dbus-1.9.14
	>=sys-apps/util-linux-2.25
	sys-process/lsof
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
	kerberos? ( app-crypt/mit-krb5 )
	wayland? ( dev-libs/wayland )
"

QA_PREBUILT="*"

# Tar extracts to Kiro/ subdirectory
S="${WORKDIR}/Kiro"

src_prepare() {
	default

	# Remove unused Chromium locale paks
	pushd "locales" > /dev/null || die
	chromium_remove_language_paks
	popd > /dev/null || die

	# Set chrome-sandbox SUID permissions
	chmod 4711 chrome-sandbox || die "Failed to set chrome-sandbox permissions"

	# Remove cross-platform binaries (~77MB savings)
	local files_removed=0

	while IFS= read -r -d '' file; do
		rm -f "${file}" && ((files_removed++))
	done < <(find "${S}" \( \
		-path "*/darwin/*" \
		-o -path "*/win32/*" \
		-o -path "*/arm64/*" \
		-o -path "*/aarch64/*" \
		-o -name "*arm64*" \
		-o -name "*.dll" \
		-o -name "*.dylib" \
	\) -type f -print0 2>/dev/null)

	# Remove Windows-only node modules
	rm -rf \
		resources/app/node_modules/windows-foreground-love \
		resources/app/extensions/kiro.kiro-agent/node_modules/win-ca \
		2>/dev/null

	find "${S}" -type d -empty -delete 2>/dev/null || true

	einfo "Removed ${files_removed} unnecessary cross-platform files"

	# Verify main binary exists
	[[ -f kiro ]] || die "Main Kiro executable not found!"
}

src_install() {
	# Disable update server
	sed -e "/updateUrl/d" -i resources/app/product.json || die

	# Remove kerberos module if not needed
	if ! use kerberos; then
		rm -rf resources/app/node_modules/kerberos || die
	fi

	# Install all application files to /opt/kiro
	insinto /opt/kiro
	doins -r .

	# Fix permissions: main executables
	fperms +x /opt/kiro/kiro
	fperms +x /opt/kiro/chrome_crashpad_handler
	fperms 4711 /opt/kiro/chrome-sandbox
	fperms +x /opt/kiro/bin/kiro

	# PaX markings for hardened kernels
	pax-mark m "${ED}"/opt/kiro/kiro

	# Fix permissions: shared libraries
	while IFS= read -r -d '' lib; do
		fperms +x "${lib#${D}}"
	done < <(find "${D}/opt/kiro" -name "*.so*" -type f -print0)

	# Symlink wrapper to /usr/bin — bin/kiro uses readlink -f to resolve /opt/kiro
	dosym -r /opt/kiro/bin/kiro /usr/bin/kiro

	# Icon — 1024x1024 PNG at resources/app/resources/linux/code.png
	local icon="resources/app/resources/linux/code.png"
	local size
	for size in 16 22 24 32 48 64 128 256 512 1024; do
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
	newbashcomp resources/completions/bash/kiro kiro
	newzshcomp resources/completions/zsh/_kiro _kiro
}

pkg_postinst() {
	xdg_pkg_postinst

	if [[ ! -x "${EROOT}/opt/kiro/kiro" ]]; then
		eerror "Kiro executable was not installed correctly!"
		eerror "Please check the installation and file a bug report."
	fi

	elog "Kiro IDE ${PV} successfully installed."
	elog "  Executable : ${EROOT}/opt/kiro/kiro"
	elog "  Wrapper    : ${EROOT}/usr/bin/kiro"
	elog "  Config     : ~/.config/kiro/"
	elog "  Docs       : https://kiro.dev/"

	optfeature "desktop notifications" x11-libs/libnotify
	optfeature "keyring support" virtual/secret-service
}

pkg_postrm() {
	xdg_pkg_postrm
}
