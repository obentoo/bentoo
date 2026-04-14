# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit systemd

DESCRIPTION="Banking security software by Topaz OFD for South American financial services"
HOMEPAGE="https://www.topaz.com.br/ofd/index.php"
SRC_URI="https://cloud.gastecnologia.com.br/bb/downloads/ws/debian/warsaw_setup64.run -> ${P}.run"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="-* ~amd64"

RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

BDEPEND="app-arch/libarchive"

RDEPEND="
	sys-apps/dbus
	sys-process/procps
	gnome-extra/zenity
	dev-lang/python:3.12
"

S="${WORKDIR}"

src_unpack() {
	local offset
	offset=$(grep -boa '!<arch>' "${DISTDIR}/${A}" | head -1 | cut -d: -f1)
	[[ -n ${offset} ]] || die "No .deb archive found inside .run binary"

	tail -c +$((offset + 1)) "${DISTDIR}/${A}" > "${T}/${P}.deb" || die

	cd "${WORKDIR}" || die
	bsdtar -xf "${T}/${P}.deb" data.tar.xz 2>/dev/null
	[[ -f data.tar.xz ]] || die "Failed to extract data.tar.xz from .deb"
	tar xJf data.tar.xz || die
	rm -f data.tar.xz || die
}

src_install() {
	# Main executables in /usr/local/bin/warsaw/
	insinto /usr/local/bin/warsaw
	insopts -m0755
	doins usr/local/bin/warsaw/*

	# Libraries in /usr/local/lib/warsaw/
	insinto /usr/local/lib/warsaw
	insopts -m0755
	doins usr/local/lib/warsaw/*.so

	# Config files in /usr/local/etc/warsaw/
	insinto /usr/local/etc/warsaw
	insopts -m0644
	doins usr/local/etc/warsaw/*

	# CLI wrapper
	dobin usr/bin/warsaw

	# Systemd service
	systemd_dounit lib/systemd/system/warsaw.service

	# OpenRC init script
	doinitd etc/init.d/warsaw

	# Man page
	doman usr/share/man/man1/warsaw.1.gz

	# Font
	insinto /usr/share/fonts/truetype
	doins usr/local/share/fonts/truetype/dbldwrsw.ttf

	# Locale
	insinto /usr/share/locale/pt_BR/LC_MESSAGES
	doins usr/share/locale/pt_BR/LC_MESSAGES/warsaw.mo
}

pkg_postinst() {
	elog "Warsaw has been installed. To start the service:"
	elog "  OpenRC: rc-service warsaw start"
	elog "  systemd: systemctl start warsaw"
	elog ""
	elog "To enable at boot:"
	elog "  OpenRC: rc-update add warsaw default"
	elog "  systemd: systemctl enable warsaw"
}
