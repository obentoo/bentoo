# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Prebuilt only. Building the cline monorepo from source was assessed and
# deferred: it is a bun workspace with ~3300 npm packages that `bun install`
# would have to fetch inside the network sandbox. See "`cline` and `kilocode`
# from source" in .autoupdate/not-packageable.md.
#
# Not to be confused with dev-util/cline-bin, the terminal CLI built from the
# same repository: that one installs /opt/bin/cline, this one cline-app, and
# the two can be installed side by side.

inherit unpacker xdg

DESCRIPTION="Cline desktop app, an autonomous AI coding agent (Tauri)"
HOMEPAGE="
	https://cline.bot/desktop
	https://github.com/cline/cline
"
# The repository tags several product lines; the desktop app's are desktop-v*.
CLINE_BASE="https://github.com/cline/cline/releases/download/desktop-v${PV}"
SRC_URI="
	amd64? ( ${CLINE_BASE}/Cline_${PV}_amd64.deb -> ${P}-amd64.deb )
"
S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
# strip: code-sidecar is a Bun single-file executable whose JavaScript payload
#        is appended to the ELF; stripping it removes the app.
# bindist: the app itself is Apache-2.0, but that sidecar bundles a few
#        thousand npm packages whose licenses nobody has enumerated, so the
#        binary is not redistributed in packaged form.
# mirror: Gentoo mirrors carry no overlay distfiles; skip the lookup.
RESTRICT="bindist mirror strip"

# cline-app NEEDED libs, plus the tray library, which Tauri dlopen()s and the
# upstream .deb lists in Depends (libayatana-appindicator3-1). code-sidecar and
# the static remote helpers need nothing beyond glibc.
RDEPEND="
	dev-libs/glib:2
	dev-libs/libayatana-appindicator
	net-libs/libsoup:3.0
	net-libs/webkit-gtk:4.1
	sys-apps/dbus
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
	x11-libs/gtk+:3
"

QA_PREBUILT="*"

src_install() {
	# The .deb layout is kept on purpose, /opt would break the app twice:
	# Tauri looks for the code-sidecar binary next to its own executable, and
	# resolves its resource directory to /usr/lib/<productName> (= Cline) only
	# when it runs from /usr/bin. The image is therefore copied as shipped:
	#   /usr/bin/{cline-app,code-sidecar}
	#   /usr/lib/Cline/{bin/remote-helpers,icons}
	#   /usr/share/{applications,icons/hicolor,metainfo}
	# Both remote helpers (x86_64 and aarch64) ship in each arch's .deb: they
	# are uploaded to the SSH host being worked on, not run locally.
	#
	# No pax-mark: it would rewrite the headers of the Bun executable.
	cp -a usr "${ED}"/ || die

	# Updater: the binary has tauri-plugin-updater built in, polling
	# .../releases/download/desktop-latest/latest.json. For a .deb build it
	# installs the update with `pkexec dpkg -i`; Gentoo has no dpkg, so an
	# accepted update fails instead of overwriting files Portage owns. There is
	# no runtime switch (environment variable or config file) to turn the
	# check off, so it is left alone; update through Portage.
}
