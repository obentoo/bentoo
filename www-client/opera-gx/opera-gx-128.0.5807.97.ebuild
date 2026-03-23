# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CHROMIUM_LANGS="
	bg bn ca cs da de el en-GB en-US es-419 es fil fi fr hi hr hu id
	it ja ko lt lv ms nb nl pl pt-BR pt-PT ro ru sk sr sv sw ta te th tr uk vi
	zh-CN zh-TW
"

inherit chromium-2 pax-utils unpacker xdg

DESCRIPTION="A fast and secure web browser with gaming features"
HOMEPAGE="https://www.opera.com/gx"

SRC_URI_BASE=(
	"https://download1.operacdn.com/ftp/pub/opera_gx"
	"https://download2.operacdn.com/ftp/pub/opera_gx"
	"https://download3.operacdn.com/ftp/pub/opera_gx"
	"https://download4.operacdn.com/ftp/pub/opera_gx"
)

MY_PN=${PN}-stable
CHROMIUM_VERSION="144"
SRC_URI="${SRC_URI_BASE[*]/%//${PV}/linux/${MY_PN}_${PV}_amd64.deb}"
S=${WORKDIR}

LICENSE="OPERA-2018"
SLOT="0"
KEYWORDS="-* amd64"
IUSE="+ffmpeg-chromium +proprietary-codecs +qt5 +suid qt6"
RESTRICT="bindist mirror strip"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-crypt/gnupg
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	gnome-base/gsettings-desktop-schemas
	media-libs/alsa-lib
	media-libs/mesa[gbm(+)]
	net-misc/curl
	net-print/cups
	sys-apps/dbus
	sys-libs/glibc
	virtual/libudev
	x11-libs/cairo
	x11-libs/gdk-pixbuf
	x11-libs/gtk+:3
	x11-libs/libdrm
	x11-libs/libxcb
	x11-libs/libxkbcommon
	x11-libs/libxshmfence
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/pango
	proprietary-codecs? (
		!ffmpeg-chromium? ( >=media-video/ffmpeg-6.1-r1:0/58.60.60[chromium] )
		ffmpeg-chromium? ( media-video/ffmpeg-chromium:${CHROMIUM_VERSION} )
	)
	qt5? (
		dev-qt/qtcore:5
		dev-qt/qtgui:5
		dev-qt/qtwidgets:5
	)
	qt6? ( dev-qt/qtbase:6[gui,widgets] )
"

BDEPEND="dev-util/desktop-file-utils"

QA_PREBUILT="*"
OPERA_HOME="opt/${MY_PN}"

pkg_pretend() {
	use amd64 || die "opera-gx only works on amd64"
}

pkg_setup() {
	chromium_suid_sandbox_check_kernel_config
}

src_unpack() {
	:
}

src_install() {
	dodir /
	cd "${ED}" || die
	unpacker

	# move to /opt
	mkdir opt || die
	mv "usr/lib/x86_64-linux-gnu/${MY_PN}" "${OPERA_HOME}" || die
	rm -r "usr/lib" || die

	# disable auto update
	rm "${OPERA_HOME}/opera_autoupdate"{,.licenses,.version} || die

	# disable crash reporting (crashpad causes segfault on non-Debian systems)
	rm -f "${OPERA_HOME}/chrome_crashpad_handler" || die
	rm -f "${OPERA_HOME}/opera_crashreporter" || die

	# remove Debian-specific files
	rm -r "usr/share/lintian" || die
	rm -f "usr/share/menu/${MY_PN}" || die

	# fix docs
	mv usr/share/doc/${MY_PN} usr/share/doc/${PF} || die
	gzip -d usr/share/doc/${PF}/changelog.gz || die

	# fix desktop file (TargetEnvironment is Unity-specific)
	sed -i \
		-e 's|^TargetEnvironment|X-&|g' \
		usr/share/applications/${PN}.desktop || die

	# remove unused language packs
	pushd "${OPERA_HOME}/localization" > /dev/null || die
	chromium_remove_language_paks
	popd > /dev/null || die

	# setup opera-gx symlink (binary is always named "opera")
	rm "usr/bin/${PN}" || die
	dosym "../../${OPERA_HOME}/opera" "/usr/bin/${PN}"

	# install proprietary codecs
	rm "${OPERA_HOME}/resources/ffmpeg_preload_config.json" || die
	if use proprietary-codecs; then
		dosym ../../usr/$(get_libdir)/chromium/libffmpeg.so$(usex ffmpeg-chromium .${CHROMIUM_VERSION} "") \
			  /${OPERA_HOME}/libffmpeg.so
	fi

	# Qt shim handling: qt5 is default, qt6 is optional
	if ! use qt5; then
		rm "${OPERA_HOME}/libqt5_shim.so" || die
	fi
	if ! use qt6; then
		rm "${OPERA_HOME}/libqt6_shim.so" || die
	fi

	# pax mark opera
	pax-mark m "${OPERA_HOME}/opera"
	# enable suid sandbox if requested
	use suid && fperms 4711 "/${OPERA_HOME}/opera_sandbox"
}

pkg_postinst() {
	xdg_pkg_postinst
}

pkg_postrm() {
	xdg_pkg_postrm
}
