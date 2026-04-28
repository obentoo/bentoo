# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CHROMIUM_LANGS="
	af am ar bg bn ca cs da de el en-GB en-US es-419 es et fa fil fi fr gu he hi
	hr hu id it ja kn ko lt lv ml mr ms nb nl pl pt-BR pt-PT ro ru sk sl sr sv sw
	ta te th tr uk ur vi zh-CN zh-TW
"

inherit chromium-2 desktop xdg

# Upstream nightly tag is rotating: only the current build is reachable
# (older dated assets get removed). Snapshot date in PV is the date this
# ebuild was bumped, NOT a stable handle.
NIGHTLY_VER="2.0.1"

DESCRIPTION="A privacy-first, open-source platform for knowledge sharing and management (nightly)"
HOMEPAGE="https://github.com/logseq/logseq"
SRC_URI="https://github.com/logseq/logseq/releases/download/nightly/Logseq-linux-x86_64-${NIGHTLY_VER}.AppImage
	-> ${P}.AppImage"

S="${WORKDIR}"

LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="wayland"

RESTRICT="bindist mirror strip"

RDEPEND="
	dev-libs/nss
	dev-libs/openssl:0/3
	media-libs/alsa-lib
	media-libs/mesa
	net-misc/curl
	net-print/cups
	sys-apps/dbus
	sys-libs/glibc
	virtual/zlib:=
	x11-libs/cairo
	x11-libs/gtk+:3
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libdrm
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/pango
"

QA_PREBUILT="*"

src_unpack() {
	cp "${DISTDIR}/${P}.AppImage" "${WORKDIR}/" || die
	chmod +x "${WORKDIR}/${P}.AppImage" || die
	"${WORKDIR}/${P}.AppImage" --appimage-extract || die
}

src_prepare() {
	default

	cd "${WORKDIR}/squashfs-root" || die
	pushd locales >/dev/null || die
	chromium_remove_language_paks
	popd >/dev/null || die
}

src_install() {
	cd "${WORKDIR}/squashfs-root" || die

	exeinto /opt/logseq-desktop
	doexe Logseq chrome-sandbox libEGL.so libffmpeg.so libGLESv2.so \
		libvk_swiftshader.so libvulkan.so.1

	insinto /opt/logseq-desktop
	doins chrome_100_percent.pak chrome_200_percent.pak icudtl.dat \
		resources.pak snapshot_blob.bin v8_context_snapshot.bin version \
		vk_swiftshader_icd.json
	insopts -m0755
	doins -r locales resources

	fowners root /opt/logseq-desktop/chrome-sandbox
	fperms 4711 /opt/logseq-desktop/chrome-sandbox

	[[ -x chrome_crashpad_handler ]] && doexe chrome_crashpad_handler

	dosym ../logseq-desktop/Logseq /opt/bin/logseq

	local exec_extra_flags=()
	if use wayland; then
		exec_extra_flags+=( "--ozone-platform-hint=auto" "--enable-wayland-ime" )
	fi
	make_desktop_entry "/opt/bin/logseq ${exec_extra_flags[*]} %U" Logseq logseq \
		"Office;" "StartupWMClass=Logseq\nMimeType=x-scheme-handler/logseq;"

	if [[ -f resources/app/icons/logseq.png ]]; then
		doicon resources/app/icons/logseq.png
	fi
}
