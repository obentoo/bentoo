# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker systemd xdg

DESCRIPTION="An open-source remote desktop, and alternative to TeamViewer (binary package)"
HOMEPAGE="https://rustdesk.com/"
SRC_URI="
	amd64? (
		https://github.com/rustdesk/rustdesk/releases/download/${PV}/rustdesk-${PV}-x86_64.deb
			-> ${P}-x86_64.deb
	)
	arm64? (
		https://github.com/rustdesk/rustdesk/releases/download/${PV}/rustdesk-${PV}-aarch64.deb
			-> ${P}-aarch64.deb
	)
"
S="${WORKDIR}"

LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"

RESTRICT="bindist mirror strip"
QA_PREBUILT="*"

RDEPEND="
	media-libs/alsa-lib
	media-libs/gst-plugins-base
	media-libs/libpulse
	media-libs/libva[X]
	media-video/pipewire[gstreamer]
	net-misc/curl
	sys-libs/pam
	x11-libs/gtk+:3
	x11-libs/libXfixes
	x11-libs/libxcb
	x11-misc/xdotool
"
# rustdesk-bin and the source build provide the same binary.
RDEPEND+=" !net-misc/rustdesk"

src_unpack() {
	unpacker_src_unpack
}

src_install() {
	# Preserve the upstream .deb FHS layout verbatim; the Flutter bundle
	# resolves its resources relative to /usr/share/rustdesk.
	cp -a etc usr "${ED}"/ || die

	# /usr/bin/rustdesk is created by the .deb postinst; recreate it here.
	dosym ../share/rustdesk/rustdesk /usr/bin/rustdesk

	# Ship the systemd unit bundled inside the data directory.
	systemd_dounit usr/share/rustdesk/files/systemd/rustdesk.service

	pax-mark m "${ED}"/usr/share/rustdesk/rustdesk
}
