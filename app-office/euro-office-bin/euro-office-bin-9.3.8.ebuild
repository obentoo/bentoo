# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop unpacker xdg

# Upstream tags a release "vX.Y.Z" and its assets "X.Y.Z-0"; a respin of the
# same version is tagged "vX.Y.Z-N" with "X.Y.Z-N" assets (v9.3.5-2). PV maps
# that respin to X.Y.Z_pN.
MY_PV=$(ver_cut 1-3)
if [[ ${PV} == *_p* ]]; then
	MY_BUILD=${PV##*_p}
	MY_TAG=v${MY_PV}-${MY_BUILD}
else
	MY_BUILD=0
	MY_TAG=v${MY_PV}
fi
MY_PN="euro-office-euro-office"
APP_DIR="opt/euro-office/euro-office"

DESCRIPTION="European fork of the ONLYOFFICE Desktop Editors office suite (binary version)"
HOMEPAGE="https://github.com/Euro-Office/DesktopEditors"
SRC_URI="https://github.com/Euro-Office/DesktopEditors/releases/download/${MY_TAG}/${MY_PN}_${MY_PV}-${MY_BUILD}_amd64.deb"
S="${WORKDIR}"

# Euro-Office itself: AGPL-3 with Ascensio's Section 7 additional terms; GUI
# art and technical writing are CC-BY-SA-4.0 (usr/share/doc/*/copyright).
# Bundled, measured on 9.3.8: CEF/Chromium (BSD), Qt 6.10.1 (LGPL-3),
# FFmpeg 7.1.2 built LGPL (LGPL-2.1+), ICU 73 and 74 (unicode),
# SingleApplication (MIT), fonts (Apache-2.0 Open Sans, OFL-1.1 Carlito,
# Caladea and Asana, OFL-1.0 OpenSymbol).
LICENSE="AGPL-3 CC-BY-SA-4.0 Apache-2.0 BSD LGPL-2.1+ LGPL-3 MIT OFL-1.0 OFL-1.1 unicode"
# Hunspell/hyphenation dictionaries under dictionaries/: most are
# GPL/LGPL/MPL tri-licensed, some GPL-2 or GPL-3 only, nl_NL is CC-BY-3.0,
# the English ones are BSD-style.
LICENSE+=" CC-BY-3.0 GPL-2 GPL-3 LGPL-2.1 MPL-1.1 MPL-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="mirror strip"

# Every soname the kept ELF files need from outside the bundle (scanelf -n,
# minus the bundle's own libraries).
RDEPEND="
	>=app-accessibility/at-spi2-core-2.46.0:2
	app-arch/brotli
	app-arch/bzip2
	app-arch/zstd
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/nspr
	dev-libs/nss
	dev-libs/wayland
	gnome-base/gsettings-desktop-schemas
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/harfbuzz
	media-libs/libglvnd
	media-libs/mesa
	net-print/cups
	sys-apps/dbus
	sys-devel/gcc
	sys-libs/glibc
	virtual/krb5
	virtual/zlib
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3[X]
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	x11-libs/libdrm
	x11-libs/libnotify
	x11-libs/libxcb
	x11-libs/libxkbcommon[X]
	x11-libs/pango
	x11-libs/xcb-util
	x11-libs/xcb-util-cursor
	x11-libs/xcb-util-image
	x11-libs/xcb-util-keysyms
	x11-libs/xcb-util-renderutil
	x11-libs/xcb-util-wm
	|| (
		media-libs/libpulse
		media-sound/apulse
	)
"
BDEPEND="dev-util/patchelf"

QA_PREBUILT="*"

src_prepare() {
	default

	# Allow launching on ALSA-only systems via media-sound/apulse
	sed -i -e "/^export LD_LIBRARY_PATH=/ s|$|:${EPREFIX}/usr/$(get_libdir)/apulse|" \
		usr/bin/${MY_PN} || die
	grep -qF "/usr/$(get_libdir)/apulse" usr/bin/${MY_PN} \
		|| die "apulse path not added to the launcher"

	# Qt SQL drivers for Oracle, Firebird, Mimer, MySQL, ODBC and PostgreSQL
	# link client libraries the bundle does not ship; only SQLite is used.
	# libQt6Quick3DSpatialAudio needs Qt Quick 3D, which is not bundled, and
	# nothing in the bundle loads it.
	rm -v ${APP_DIR}/sqldrivers/libqsql{ibase,mimer,mysql,oci,odbc,psql}.so \
		${APP_DIR}/libQt6Quick3DSpatialAudio.so* || die

	# Empty directory trees left over from the Qt build, and a dev helper
	# that only works when run from inside the install directory.
	rm -r ${APP_DIR}/{cmake,objects-RelWithDebInfo,pkgconfig} \
		${APP_DIR}/start_desktop.sh || die

	# The bundled ICU 74 carries a mangled DT_RPATH that ends in the
	# builder's absolute path (RIGIN:$ORIGIN:/core/build/third_party/...).
	# Its libraries only need each other, so $ORIGIN is enough.
	local lib
	for lib in ${APP_DIR}/{,converter/}libicu*.so.74.*; do
		patchelf --set-rpath '$ORIGIN' "${lib}" || die
	done
}

src_install() {
	# usr/bin/desktopeditors (a symlink to the launcher) is left out on
	# purpose: app-office/onlyoffice-bin installs the same path.
	dobin usr/bin/${MY_PN}
	domenu usr/share/applications/${MY_PN}.desktop
	local size
	for size in 16 24 32 48 64 128 256; do
		doicon -s ${size} usr/share/icons/hicolor/${size}x${size}/apps/${MY_PN}.png
	done

	insinto /opt
	doins -r opt/euro-office
	fperms +x /${APP_DIR}/{DesktopEditors,editors_helper,converter/x2t}
}
