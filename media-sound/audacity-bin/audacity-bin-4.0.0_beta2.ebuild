# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

# Upstream tag: Audacity-4.0.0-beta-2 (with hyphen before the beta number)
# AppImage filename: Audacity-4.0.0-beta2-x86_64.AppImage (no hyphen)
MY_TAG="Audacity-${PV/_beta/-beta-}"
MY_APPIMAGE="Audacity-${PV/_beta/-beta}-x86_64.AppImage"

DESCRIPTION="Multi-track audio editor and recorder (official Audacity 4 AppImage)"
HOMEPAGE="https://www.audacityteam.org/"
SRC_URI="https://github.com/audacity/audacity/releases/download/${MY_TAG}/${MY_APPIMAGE} -> ${P}.AppImage"
S="${WORKDIR}"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

# The AppImage bundles Qt6, wxWidgets and the audio codec stack internally.
# These are the external system libraries the main binary and AppRun expect
# to resolve at runtime (see readelf NEEDED / ldd on usr/bin/audacity4portable).
RDEPEND="
	dev-libs/expat
	dev-libs/glib:2
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/libglvnd
	virtual/opengl
	virtual/zlib
	x11-libs/libX11
	x11-libs/libxcb
"

# Real binary lives at usr/bin/audacity4portable inside the AppImage.
MY_BIN="audacity4portable"

src_unpack() {
	cp "${DISTDIR}/${P}.AppImage" "${WORKDIR}/${P}.AppImage" || die
	chmod +x "${WORKDIR}/${P}.AppImage" || die
	cd "${WORKDIR}" || die
	"./${P}.AppImage" --appimage-extract > /dev/null || die
	rm -f "${WORKDIR}/${P}.AppImage" || die
}

src_install() {
	local dest="/opt/${PN}"

	# Install the fully self-contained bundle. The AppImage ships a portable
	# layout (bin/, lib/, lib/audacity/, plugins/, qml/, fallback/, share/,
	# translations/) plus its own AppRun launcher that sets APPDIR /
	# LD_LIBRARY_PATH and loads jack/nss fallbacks when the system lacks them.
	insinto "${dest}"
	doins -r squashfs-root/.
	chmod -R a+rX "${ED}${dest}" || die
	fperms +x \
		"${dest}/AppRun" \
		"${dest}/usr/bin/${MY_BIN}" \
		"${dest}/usr/bin/crashpad_handler" \
		"${dest}/usr/bin/findlib" \
		"${dest}/usr/bin/ldd-recursive" \
		"${dest}/usr/bin/portable-utils" \
		"${dest}/usr/bin/rm-empty-dirs"

	# Launch through the bundled AppRun so APPDIR / LD_LIBRARY_PATH / fallback
	# resolution matches upstream. Expose it under a distinct name so it never
	# collides with a from-source media-sound/audacity in /usr/bin/audacity.
	dosym "../${PN}/AppRun" /opt/bin/audacity-bin

	# Desktop entry: rewrite Exec/Icon to our install and a stable menu name.
	sed \
		-e "s|^Exec=.*|Exec=audacity-bin %U|" \
		-e "s|^Icon=.*|Icon=audacity-bin|" \
		-e "s|^Name=.*|Name=Audacity 4|" \
		squashfs-root/share/applications/org.audacityteam.Audacity4portable.desktop \
		> "${T}/audacity-bin.desktop" || die
	domenu "${T}/audacity-bin.desktop"

	# Icons (rename hicolor app icons to match Icon=audacity-bin).
	local size
	for size in 16 24 32 48 64 96 128 512; do
		newicon -s "${size}" \
			"squashfs-root/share/icons/hicolor/${size}x${size}/apps/audacity4portable.png" \
			audacity-bin.png
	done
}
