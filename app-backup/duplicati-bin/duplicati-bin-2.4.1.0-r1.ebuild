# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

# Upstream tags and release assets embed a channel and build date
# (e.g. "v2.3.0.4_stable_2026-07-09"), which is not a valid Gentoo version
# suffix. Keep PV clean ("2.3.0.4") and reconstruct the upstream naming here.
MY_CHANNEL="stable"
MY_DATE="2026-10-29"
MY_TAG="v${PV}_${MY_CHANNEL}_${MY_DATE}"
MY_ASSET="duplicati-${PV}_${MY_CHANNEL}_${MY_DATE}"

DESCRIPTION="Free backup client with strong encryption, deduplication and cloud storage (GUI binary)"
HOMEPAGE="https://duplicati.com https://github.com/duplicati/duplicati"
SRC_URI="
	amd64? (
		https://github.com/duplicati/duplicati/releases/download/${MY_TAG}/${MY_ASSET}-linux-x64-gui.zip
			-> ${P}-linux-x64-gui.zip
	)
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

# Self-contained .NET bundle: the runtime is embedded, but the native
# interop libraries dlopen a handful of system libraries at runtime, and the
# Avalonia (X11) tray + SkiaSharp renderer need the X11/GL/font stack.
RDEPEND="
	dev-libs/icu
	|| (
		dev-libs/openssl-compat:3
		dev-libs/openssl:0/3
	)
	media-libs/fontconfig
	media-libs/freetype
	media-libs/mesa
	sys-libs/zlib
	x11-libs/libICE
	x11-libs/libSM
	x11-libs/libX11
	x11-libs/libXext
"

QA_PREBUILT="
	opt/duplicati-bin/createdump
	opt/duplicati-bin/duplicati
	opt/duplicati-bin/duplicati-*
	opt/duplicati-bin/*.so
"

# Native launchers shipped by the self-contained bundle. doins strips the
# executable bit, so it is re-applied explicitly below.
DUPLICATI_LAUNCHERS=(
	duplicati
	duplicati-aescrypt
	duplicati-autoupdater
	duplicati-backend-tester
	duplicati-backend-tool
	duplicati-cli
	duplicati-database-tool
	duplicati-recovery-tool
	duplicati-secret-tool
	duplicati-server
	duplicati-server-util
	duplicati-service
	duplicati-snapshots
	duplicati-source-tool
	duplicati-sync-tool
)

src_unpack() {
	default
	# The zip extracts to a single top-level directory whose name embeds the
	# arch and build date (duplicati-<ver>_stable_<date>-linux-<arch>-gui).
	# Resolve S dynamically instead of hardcoding it.
	S=$(echo "${WORKDIR}"/duplicati-*-gui)
}

src_install() {
	# Install the whole self-contained tree (flat DLL layout plus webroot/,
	# licenses/, utility-scripts/, lvm-scripts/) under /opt.
	insinto /opt/duplicati-bin
	doins -r .

	# Restore the executable bit on the native launchers and the .NET crash
	# dumper. doins removes it during installation.
	local b
	fperms +x /opt/duplicati-bin/createdump
	for b in "${DUPLICATI_LAUNCHERS[@]}"; do
		fperms +x "/opt/duplicati-bin/${b}"
	done
	# Helper shell scripts shipped alongside the launchers.
	for b in run-script-example.sh set-permissions.sh; do
		[[ -f ${b} ]] && fperms +x "/opt/duplicati-bin/${b}"
	done

	# Canonical CLI/server entry points in PATH. No source ebuild of
	# app-backup/duplicati exists in this overlay, so the canonical names are
	# safe to use without collision.
	dosym ../../opt/duplicati-bin/duplicati /usr/bin/duplicati
	dosym ../../opt/duplicati-bin/duplicati-cli /usr/bin/duplicati-cli
	dosym ../../opt/duplicati-bin/duplicati-server /usr/bin/duplicati-server

	# The bundle ships no application icon or .desktop file; provide both.
	# Use the official 512x512 Duplicati logo vendored in files/ (the bundle
	# carries only tiny web favicons and a rectangular wordmark SVG).
	newicon -s 512 "${FILESDIR}"/duplicati.png duplicati.png

	# Write the .desktop by hand. Do NOT pass TryExec/Comment through
	# make_desktop_entry's 5th "fields" arg: the eclass already emits those
	# keys, so the file ends up with duplicate Comment=/TryExec= keys. That is
	# an invalid .desktop (desktop-file-validate errors out), and KDE's
	# kbuildsycoca then drops the entry, so it never shows in the menu.
	cat > "${T}"/duplicati.desktop <<-EOF || die
		[Desktop Entry]
		Type=Application
		Name=Duplicati
		GenericName=Backup Tool
		Comment=Store encrypted, incremental, deduplicated backups online
		Exec=/opt/duplicati-bin/duplicati
		TryExec=/opt/duplicati-bin/duplicati
		Icon=duplicati
		Terminal=false
		Categories=Utility;Archiving;
		Keywords=backup;restore;encryption;cloud;
		StartupNotify=true
		StartupWMClass=Duplicati
	EOF
	domenu "${T}"/duplicati.desktop

	dodoc changelog.txt licenses/license.txt
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Duplicati (self-contained GUI binary) installed under /opt/duplicati-bin."
	elog ""
	elog "Launch the tray/web UI with:  duplicati"
	elog "Command-line client:          duplicati-cli"
	elog "Headless server:              duplicati-server"
	elog ""
	elog "The web UI is served locally; open http://localhost:8200 after starting"
	elog "the tray icon or the server."
}

pkg_postrm() {
	xdg_pkg_postrm
}
