# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CHROMIUM_LANGS="af am ar bg bn ca cs da de el en-GB es es-419 et fa fi fil fr gu
	he hi hr hu id it ja kn ko lt lv ml mr ms nb nl pl pt-BR pt-PT ro ru sk sl
	sr sv sw ta te th tr uk ur vi zh-CN zh-TW"

inherit chromium-2 desktop optfeature pax-utils unpacker xdg

# curl -sA 'Mozilla/5.0' "https://claude.ai/api/desktop/linux/x64/deb/latest" | jq -r '.url'
BUILD_ID="df1d8a339dfabcf359af7144fe142b59ff7d9a0f"

MY_PN="${PN%-bin}"

DESCRIPTION="Desktop application for Claude.ai"
HOMEPAGE="https://claude.ai/ https://code.claude.com/docs/en/desktop-linux"
SRC_URI="https://downloads.claude.ai/releases/linux/x64/${PV}/Claude-${BUILD_ID}.deb
	-> ${P}.deb"
S="${WORKDIR}"

# Anthropic proprietary app; MIT covers the bundled Electron/Chromium runtime.
LICENSE="all-rights-reserved MIT"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="egl wayland"
RESTRICT="bindist mirror strip"

RDEPEND="
	|| (
		sys-apps/systemd
		sys-apps/systemd-utils
	)
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/libsecret
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	sys-apps/util-linux
	sys-apps/xdg-desktop-portal
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libxkbcommon
	x11-libs/libXrandr
	x11-libs/libXtst
	x11-libs/pango
	x11-misc/xdg-utils
"

QA_PREBUILT="*"

CLAUDE_HOME="usr/lib/${MY_PN}"

src_prepare() {
	default

	pushd "${CLAUDE_HOME}/locales" >/dev/null || die
	chromium_remove_language_paks
	popd >/dev/null || die
}

src_install() {
	dodir "/opt/${MY_PN}"
	cp -ar "${CLAUDE_HOME}/." "${ED}/opt/${MY_PN}/" || die

	fperms 4711 "/opt/${MY_PN}/chrome-sandbox"
	pax-mark m "${ED}/opt/${MY_PN}/${MY_PN}"
	dosym -r "/opt/${MY_PN}/${MY_PN}" "/opt/bin/${MY_PN}"

	local EXEC_EXTRA_FLAGS=()
	if use wayland; then
		EXEC_EXTRA_FLAGS+=( "--ozone-platform-hint=auto" "--enable-wayland-ime" "--wayland-text-input-version=3" )
	fi
	if use egl; then
		EXEC_EXTRA_FLAGS+=( "--use-gl=egl" )
	fi

	# Upstream already ships Exec=claude-desktop / Icon=claude-desktop, so only
	# the extra flags are spliced in -- including into the Desktop Actions.
	sed -e "s|^Exec=${MY_PN}|Exec=${MY_PN} ${EXEC_EXTRA_FLAGS[*]}|" \
		"usr/share/applications/com.anthropic.Claude.desktop" \
		>"${T}/${MY_PN}.desktop" || die
	domenu "${T}/${MY_PN}.desktop"

	local size
	for size in 16 32 48 128 256; do
		doicon -s "${size}" "usr/share/icons/hicolor/${size}x${size}/apps/${MY_PN}.png"
	done
}

pkg_postinst() {
	xdg_pkg_postinst

	optfeature "sandboxed code execution in a virtual machine" \
		"app-emulation/qemu sys-firmware/edk2-ovmf app-emulation/virtiofsd"
	optfeature "system tray icon" x11-libs/libayatana-appindicator
	optfeature "storing credentials in a keyring" virtual/secret-service
}
