# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

MY_PN="audacity"

# Upstream renamed every Linux asset at the 4.0.0 stable release:
#   beta   tag Audacity-4.0.0-beta-4  file Audacity-4.0.0-beta4-x86_64.AppImage
#   stable tag Audacity-4.0.0         file audacity-linux-4.0.0-x86_64.AppImage
# Only the stable scheme is expressed here. A future pre-release must have its
# own derivation checked against the actual release assets -- the two schemes
# agree on nothing, not even the capitalisation, so it cannot be extrapolated.
MY_TAG="Audacity-${PV}"

DESCRIPTION="Multi-track audio editor and recorder (official Audacity 4 AppImage)"
HOMEPAGE="https://www.audacityteam.org/"
SRC_URI="
	amd64? (
		https://github.com/audacity/audacity/releases/download/${MY_TAG}/${MY_PN}-linux-${PV}-x86_64.AppImage
			-> ${P}-x86_64.AppImage
	)
"
S="${WORKDIR}"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

# Measured on the 4.0.1 payload, by walking every bundled ELF and keeping the
# NEEDED entries that resolve outside lib/ and fallback/. Qt6, wxWidgets, the
# codec stack, krb5, harfbuzz and freetype are all bundled and must NOT be
# listed here -- an earlier revision of this ebuild depended on expat, freetype
# and zlib, none of which the payload actually resolves from the system.
#
#   libX11 / libX11-xcb ... main binary + plugins/platforms/libqxcb.so
#   libxcb ............... plugins/platforms/libqxcb.so
#   libwayland-{client,egl} plugins/platforms/libqwayland.so and friends
#   libglib-2.0 et al .... libQt6Core / libQt6Gui / libQt6XcbQpa
#   libfontconfig ........ libQt6Gui
#   libEGL/libGL/libGLX/libOpenGL  libQt6Gui + the GL integration plugins
#   libasound ............ main binary
#   libcom_err ........... bundled libkrb5, reached from libQt6Network via the
#                          bundled libgssapi_krb5 -- a hard load-time edge
#   libdbus-1 ............ libQt6DBus, no longer bundled since 4.0.1
#
# libgpg-error also shows up unresolved, but only from the orphaned bundled
# libgcrypt that nothing loads -- not a real edge, see src_prepare.
# Deliberately absent: x11-libs/gtk+:3, needed only by the optional
# plugins/platformthemes/libqgtk3.so, which Qt loads under GNOME and otherwise
# never touches; and dev-libs/nss plus dev-db/sqlite, reachable only through
# the bundled fallback/libnss3.so, which AppRun loads only when the system has
# no libnss3 of its own.
RDEPEND="
	dev-libs/glib:2
	dev-libs/wayland
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/libglvnd
	sys-apps/dbus
	sys-fs/e2fsprogs
	virtual/opengl
	x11-libs/libX11
	x11-libs/libxcb
"

# Real binary lives at bin/audacity4portable inside the AppImage ("portable"
# build, not "audacity"). usr/ is a symlink to "." in the payload, so
# usr/bin/<x> and bin/<x> are the same file.
MY_BIN="audacity4portable"

src_unpack() {
	local appimage
	if use amd64; then
		appimage="${P}-x86_64.AppImage"
	else
		die "no upstream AppImage for this arch"
	fi

	cp "${DISTDIR}/${appimage}" "${WORKDIR}/${appimage}" || die
	chmod +x "${WORKDIR}/${appimage}" || die
	cd "${WORKDIR}" || die
	"./${appimage}" --appimage-extract > /dev/null || die
	rm -f "${WORKDIR}/${appimage}" || die
}

src_prepare() {
	default

	# Up to 4.0.0 the payload bundled libdbus-1.so.3 built on a systemd CI
	# runner, carrying NEEDED libsystemd.so.0. Nothing in ::gentoo provides
	# that soname outside sys-apps/systemd, so on an OpenRC or musl host the
	# loader failed on it and Audacity did not start at all (libQt6DBus.so.6
	# is a NEEDED of the main binary). The 4.0.0 ebuild deleted the bundled
	# copy; since 4.0.1 upstream no longer ships it, and libQt6DBus resolves
	# the system sys-apps/dbus on its own. Its leftover deps (libgcrypt, lz4,
	# libcap, lzma) are still in lib/ but nothing loads them.
	#
	# Guard the property, not the file: if any bundled object asks for
	# libsystemd.so.0 again, a non-systemd host cannot start the program.
	local offenders
	offenders=$(grep -rlF libsystemd.so.0 squashfs-root) && \
		die "payload links libsystemd.so.0 again, breaking non-systemd hosts:"$'\n'"${offenders}"

	# Upstream ships the CMake install manifest inside the AppImage. Every line
	# is an absolute path from the GitHub runner that produced it
	# (/home/runner/work/audacity/...), which is a build-path leak and of no
	# use on a user's machine.
	rm -f squashfs-root/install_manifest.txt || die
}

src_install() {
	local dest="/opt/${PN}"

	# Install the fully self-contained bundle. The AppImage ships a portable
	# layout (bin/, lib/, lib/audacity/, plugins/, qml/, fallback/, share/,
	# translations/) plus its own AppRun launcher that sets APPDIR /
	# LD_LIBRARY_PATH and loads jack/nss fallbacks when the system lacks them.
	# doins -r preserves symlinks in EAPI 8, which matters here: the payload
	# contains "usr -> .", and a follow-symlinks copy would recurse forever.
	insinto "${dest}"
	doins -r squashfs-root/.
	chmod -R a+rX "${ED}${dest}" || die
	fperms +x \
		"${dest}/AppRun" \
		"${dest}/bin/${MY_BIN}" \
		"${dest}/bin/crashpad_handler" \
		"${dest}/bin/findlib" \
		"${dest}/bin/ldd-recursive" \
		"${dest}/bin/portable-utils" \
		"${dest}/bin/rm-empty-dirs" \
		"${dest}/wrappers/xdg-open"

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

	# Icons (rename hicolor app icons to match Icon=audacity-bin). These are
	# the eight sizes the payload actually ships under apps/; it also carries
	# mimetype icons, which are left alone because the .desktop's MimeType is
	# not registered here.
	local size
	for size in 16 24 32 48 64 96 128 512; do
		newicon -s "${size}" \
			"squashfs-root/share/icons/hicolor/${size}x${size}/apps/audacity4portable.png" \
			audacity-bin.png
	done
}
