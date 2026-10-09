# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module desktop systemd xdg

DESCRIPTION="Tray icon and desktop notifications for bentoo overlay notices"
HOMEPAGE="https://github.com/obentoo/bentoolkit"
# bentoo-tray is the second binary of the bentoolkit repository and carries a
# version of its own (internal/tray/version/VERSION); BENTOOLKIT_PV is the
# bentoolkit release that ships this tray version. It shares
# app-portage/bentoolkit's distfile rather than fetching the same tag twice.
BENTOOLKIT_PV="0.34.0"
SRC_URI="https://github.com/obentoo/bentoolkit/archive/refs/tags/v${BENTOOLKIT_PV}.tar.gz -> bentoolkit-${BENTOOLKIT_PV}.tar.gz"
S="${WORKDIR}/bentoolkit-${BENTOOLKIT_PV}"

LICENSE="MIT"
SLOT="0"
# Pure Go built with CGO_ENABLED=0, and upstream's Makefile cross-builds an
# arm64 binary of it, so ~arm64 is upstream-supported.
KEYWORDS="~amd64 ~arm64 ~x86"
IUSE="systemd"
# Same module fetch as app-portage/bentoolkit: `ego mod download` needs the
# network in src_unpack.
RESTRICT="network-sandbox"

# Everything else it talks to is a D-Bus service of the desktop session (the
# notification server, the StatusNotifierHost, the OpenURI portal, and
# NetworkManager, which is optional), spoken by godbus in pure Go -- no library
# to link. The installed-package list (/var/db/pkg) and the news unread file
# (/var/lib/gentoo/news) come from Portage itself. xdg-open is the fallback
# when the portal is missing or fails (internal/desktop/portal/portal.go).
RDEPEND="x11-misc/xdg-utils"
# go.mod declares go 1.27.0 with toolchain go1.27.2, but the Go that builds
# this package decides the standard library it links: 1.27.1 carries 13
# stdlib advisories (GO-2026-6599..6617), all fixed in 1.27.2.
BDEPEND=">=dev-lang/go-1.27.2"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_prepare() {
	default
	# The binary reports the embedded VERSION, not ${PV}: refuse a pairing in
	# which the package and the tray would claim different versions.
	local tray_pv
	tray_pv=$(<internal/tray/version/VERSION) || die
	[[ ${tray_pv} == "${PV}" ]] ||
		die "bentoolkit ${BENTOOLKIT_PV} ships bentoo-tray ${tray_pv}, not ${PV}"
}

src_compile() {
	local version_pkg="github.com/obentoo/bentoolkit/internal/common/version"
	local build_date=$(date -u '+%Y-%m-%d_%H:%M:%S')
	# The tray's own version is embedded from VERSION; this is the bentoolkit
	# release that --version prints on its second line.
	local ldflags="-X ${version_pkg}.Version=${BENTOOLKIT_PV}"
	ldflags+=" -X ${version_pkg}.Commit=release"
	ldflags+=" -X ${version_pkg}.BuildDate=${build_date}"

	# Upstream builds the tray pure Go: its D-Bus client needs no C library.
	CGO_ENABLED=0 ego build -ldflags "${ldflags}" -o bentoo-tray ./cmd/bentoo-tray
}

src_install() {
	dobin bentoo-tray
	domenu misc/tray/bentoo-tray.desktop
	local icon
	for icon in bentoo-tray bentoo-tray-unread bentoo-tray-critical; do
		doicon -s scalable misc/tray/icons/${icon}.svg
	done

	# A *user* unit: the tray needs the session bus of a logged-in desktop.
	if use systemd; then
		sed "s|@BINDIR@|${EPREFIX}/usr/bin|g" misc/tray/bentoo-tray.service.in \
			> "${T}"/bentoo-tray.service || die
		systemd_douserunit "${T}"/bentoo-tray.service
	fi

	# Same scope for hosts without systemd; never gated on USE=systemd.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/bentoo-tray.initd bentoo-tray

	dodoc docs/tray.md
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "bentoo-tray shows the bentoo overlay's notices and unread news items"
	elog "for packages installed from ::bentoo. Start it from inside your desktop"
	elog "session, with one of:"
	elog "  cp /usr/share/applications/bentoo-tray.desktop ~/.config/autostart/"
	if use systemd; then
		elog "  systemctl --user enable --now bentoo-tray.service"
	fi
	elog "  rc-service --user bentoo-tray start   (OpenRC)"
	elog
	elog "Settings live in the tray: section of ~/.config/bentoo/config.yaml;"
	elog "see /usr/share/doc/${PF}/tray.md*."
	elog
	elog "GNOME has no tray of its own: install and enable"
	elog "gnome-shell-extension-appindicator to see the icon. Notifications work"
	elog "without it. KDE Plasma shows the icon natively."
}
