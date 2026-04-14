# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker systemd

DESCRIPTION="Banking security software by Topaz OFD for South American financial services"
HOMEPAGE="https://www.topaz.com.br/ofd/index.php"
SRC_URI="https://cloud.gastecnologia.com.br/bb/downloads/ws/debian/warsaw_setup64.run -> ${P}.run"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="-* ~amd64"

RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

RDEPEND="
	sys-apps/dbus
	sys-process/procps
	gnome-extra/zenity
	dev-lang/python:3.12
"

S="${WORKDIR}"

src_unpack() {
	bash "${DISTDIR}/${P}.run" --noexec --target "${T}/run_extract" || die "Failed to extract makeself archive"

	local deb
	deb=$(find "${T}/run_extract" -name '*.deb' -print -quit)
	[[ -n ${deb} ]] || die "No .deb found inside makeself archive"

	cp "${deb}" "${WORKDIR}/warsaw.deb" || die
	unpack_deb "${WORKDIR}/warsaw.deb"
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
