# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# NAMING: the package is dev-util/codex-desktop-bin, but everything upstream
# ships is called "chatgpt" -- the Debian package name, the payload directory
# (/usr/lib/chatgpt), the launcher symlink (/usr/bin/chatgpt) and the .desktop
# entry. This is not a mistake: OpenAI unified ChatGPT, ChatGPT Work and Codex
# into a single desktop app whose Linux build is published under the Codex
# brand (HOMEPAGE is developers.openai.com/codex/app, the APT repo is
# codex-app-prod, the internal launcher is called codex-launcher). We keep the
# "codex-desktop" name so the package sits next to dev-util/codex (the Rust
# CLI) and dev-util/codex-bin, and we keep the "chatgpt" command name so that
# the upstream .desktop entry, the x-scheme-handler/codex handler and any
# documentation that says "run chatgpt" keep working.

inherit desktop optfeature pax-utils unpacker xdg

# Upstream ships only .deb (the /rpm/ path of the same CDN 404s). Always use
# the versioned pool URL: .../deb/latest/chatgpt_amd64.deb also resolves but is
# a moving alias and therefore unusable as a distfile.
MY_PN="chatgpt"
OAI_BASE="https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/${MY_PN}"

DESCRIPTION="OpenAI Codex/ChatGPT desktop application (Electron, proprietary)"
HOMEPAGE="https://developers.openai.com/codex/app"
SRC_URI="
	amd64? ( ${OAI_BASE}/${MY_PN}_${PV}_amd64.deb -> ${P}-amd64.deb )
	arm64? ( ${OAI_BASE}/${MY_PN}_${PV}_arm64.deb -> ${P}-arm64.deb )
"
S="${WORKDIR}"

# OpenAI proprietary application; the only license text shipped inside the
# package is usr/share/doc/chatgpt/copyright (MIT, for the bundled Electron
# runtime) plus usr/lib/chatgpt/LICENSES.chromium.html. No OpenAI license file
# is included, so the app itself is all-rights-reserved.
LICENSE="all-rights-reserved MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="apparmor egl wayland"
RESTRICT="bindist mirror strip"

RDEPEND="
	app-accessibility/at-spi2-core:2
	app-arch/xz-utils
	app-misc/ca-certificates
	dev-libs/expat
	dev-libs/glib:2
	dev-libs/libusb:1
	dev-libs/nspr
	dev-libs/nss
	dev-libs/openssl:0/3
	media-gfx/graphite2
	media-libs/alsa-lib
	media-libs/libglvnd
	media-libs/mesa[gbm(+)]
	net-print/cups
	sys-apps/dbus
	virtual/libudev:=
	x11-libs/cairo
	x11-libs/gdk-pixbuf:2
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
	x11-libs/pango
	x11-misc/xdg-utils
	apparmor? ( sys-apps/apparmor )
"

QA_PREBUILT="*"

# Payload lives in usr/lib/chatgpt inside the .deb.
CODEX_SRCDIR="usr/lib/${MY_PN}"
CODEX_DESTDIR="/opt/${PN%-bin}"

src_install() {
	dodir "${CODEX_DESTDIR}"
	cp -a "${CODEX_SRCDIR}/." "${ED}${CODEX_DESTDIR}/" || die

	# This Electron build ships NO setuid chrome-sandbox helper: it relies on
	# unprivileged user namespaces instead (upstream even ships an AppArmor
	# profile whose only rule is "userns,"). Hence no `fperms 4711` here --
	# see pkg_postinst for the kernel requirement.
	pax-mark m "${ED}${CODEX_DESTDIR}/ChatGPT"

	# codex-launcher resolves its own path with `readlink -f "$0"` and then
	# execs ./ChatGPT next to it, so it is symlink-safe by design and no
	# wrapper script is needed.
	dosym -r "${CODEX_DESTDIR}/codex-launcher" "/opt/bin/${MY_PN}"
	dosym -r "${CODEX_DESTDIR}/codex-launcher" "/opt/bin/${PN%-bin}"

	local exec_flags=()
	if use wayland; then
		exec_flags+=(
			--ozone-platform-hint=auto
			--enable-wayland-ime
			--wayland-text-input-version=3
		)
	fi
	if use egl; then
		exec_flags+=( --use-gl=egl )
	fi

	# Upstream ships Exec=chatgpt %U / Icon=chatgpt; only splice in the flags.
	sed -e "s|^Exec=${MY_PN}|Exec=${MY_PN} ${exec_flags[*]}|" \
		"usr/share/applications/${MY_PN}.desktop" \
		>"${T}/${PN%-bin}.desktop" || die
	domenu "${T}/${PN%-bin}.desktop"

	# Only one icon is shipped, a 1024x1024 PNG.
	newicon -s 1024 "usr/share/pixmaps/${MY_PN}.png" "${MY_PN}.png"

	if use apparmor; then
		insinto /etc/apparmor.d
		doins "etc/apparmor.d/${MY_PN}"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "The ${PN%-bin} binary is installed as both /opt/bin/${MY_PN} and"
	elog "/opt/bin/${PN%-bin}; upstream calls the command 'chatgpt'."
	elog
	elog "This build has no setuid chrome-sandbox helper: the renderer sandbox"
	elog "needs unprivileged user namespaces (CONFIG_USER_NS=y and"
	elog "kernel.unprivileged_userns_clone / user.max_user_namespaces > 0)."
	elog "Without them the app only starts with --no-sandbox, which is not"
	elog "recommended."

	optfeature "repository operations from the Codex agent" dev-vcs/git
	optfeature "system tray icon" x11-libs/libayatana-appindicator
	optfeature "audio playback via PulseAudio/PipeWire" media-libs/libpulse
}
