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
"
S="${WORKDIR}"

LICENSE="AGPL-3"
SLOT="0"
KEYWORDS="-* ~amd64"
# `systemd` gates the unit ONLY. The OpenRC init script is installed
# unconditionally -- see src_install.
IUSE="systemd"

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

	# OpenRC service, installed unconditionally: it costs a systemd user
	# nothing, while gating it would leave an OpenRC user with no way to run
	# the daemon this package exists to provide. The file is byte-identical
	# to net-misc/rustdesk/files/rustdesk.initd -- FILESDIR is per-package,
	# so it has to be duplicated rather than shared.
	newinitd "${FILESDIR}"/rustdesk.initd rustdesk

	# Ship the systemd unit bundled inside the data directory.
	#
	# Gating this call is sufficient, which is not obvious given the `cp -a`
	# above copies the whole .deb payload. Measured on the 1.4.9 x86_64
	# payload (re-checked 2026-08-08): its only .service file is the SOURCE
	# named here, usr/share/rustdesk/files/systemd/rustdesk.service. systemd
	# does not read /usr/share, so no active unit path is populated by the
	# payload itself, and ./etc holds only pam.d and rustdesk config.
	# RE-CHECK THIS AFTER A VERSION BUMP: the payload layout is upstream's to
	# change, and a unit appearing under ./etc or ./usr/lib would defeat the
	# gate silently.
	#
	# That source file stays under /usr/share with USE=-systemd. It is inert
	# there and is deliberately left in place: excising one file would mean
	# special-casing the verbatim payload copy this ebuild exists to preserve.
	if use systemd; then
		systemd_dounit usr/share/rustdesk/files/systemd/rustdesk.service
	fi

	pax-mark m "${ED}"/usr/share/rustdesk/rustdesk
}
