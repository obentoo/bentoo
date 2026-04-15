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
	dev-lang/python:3=
	gnome-extra/zenity
	sys-fs/e2fsprogs
"

S="${WORKDIR}"

src_unpack() {
	cd "${WORKDIR}" || die
	bsdtar -xpf "${DISTDIR}/${A}" || die
	bsdtar -xf warsaw_setup/warsaw_*.deb data.tar.xz || die
	tar xJf data.tar.xz || die
	rm -f data.tar.xz || die
}

src_install() {
	exeinto /usr/local/bin/warsaw
	doexe usr/local/bin/warsaw/core
	doexe usr/local/bin/warsaw/sysdss
	doexe usr/local/bin/warsaw/wsatspi
	doexe usr/local/bin/warsaw/wsupdsl

	exeinto /usr/local/lib/warsaw
	doexe usr/local/lib/warsaw/*.so

	insinto /usr/local/etc/warsaw
	doins usr/local/etc/warsaw/*

	dobin usr/bin/warsaw

	systemd_dounit lib/systemd/system/warsaw.service

	doinitd etc/init.d/warsaw

	doman usr/share/man/man1/warsaw.1.gz

	insinto /usr/share/fonts/truetype
	doins usr/local/share/fonts/truetype/dbldwrsw.ttf

	insinto /usr/share/locale/pt_BR/LC_MESSAGES
	doins usr/share/locale/pt_BR/LC_MESSAGES/warsaw.mo

	dodoc usr/share/doc/warsaw/copyright
}

pkg_postinst() {
	if type -P execstack &>/dev/null; then
		execstack -s "${EROOT}/usr/local/bin/warsaw/core" || ewarn "execstack failed"
	else
		ewarn "execstack not found. Warsaw may not work correctly in browsers."
		ewarn "If you experience issues, install execstack and run:"
		ewarn "  execstack -s /usr/local/bin/warsaw/core"
	fi

	chattr +i "${EROOT}/usr/local/bin/warsaw/core" 2>/dev/null
	chattr +a "${EROOT}/usr/local/bin/warsaw/" 2>/dev/null

	elog "Warsaw has been installed. To start the service:"
	elog "  OpenRC: rc-service warsaw start"
	elog "  systemd: systemctl start warsaw"
	elog ""
	elog "To enable at boot:"
	elog "  OpenRC: rc-update add warsaw default"
	elog "  systemd: systemctl enable warsaw"
	elog ""
	elog "After starting, complete your bank setup at:"
	elog "  Banco do Brasil: https://seg.bb.com.br"
	elog "  Caixa Econômica Federal: https://imagem.caixa.gov.br/asc/diagnostico.htm"
	elog "  Sicredi: https://www.sicredi.com.br/diagnostico/html/modulo/index.html"
}

pkg_prerm() {
	chattr -i "${EROOT}/usr/local/bin/warsaw/core" 2>/dev/null
	chattr -a "${EROOT}/usr/local/bin/warsaw/" 2>/dev/null
}
