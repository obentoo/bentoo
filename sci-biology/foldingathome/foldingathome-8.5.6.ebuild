# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop systemd unpacker xdg

DESCRIPTION="Folding@Home distributed computing client for protein folding research"
HOMEPAGE="https://foldingathome.org/"

BASE_URI="https://download.foldingathome.org/releases/public/fah-client"
SRC_URI="
	amd64? ( ${BASE_URI}/debian-10-64bit/release/fah-client_${PV}_amd64.deb -> ${P}-amd64.deb )
	arm64? ( ${BASE_URI}/debian-stable-arm64/release/fah-client_${PV}_arm64.deb -> ${P}-arm64.deb )
"
S="${WORKDIR}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

RDEPEND="
	acct-group/foldingathome
	acct-user/foldingathome
	dev-libs/openssl:=
	sys-libs/glibc
	sys-libs/zlib:=
"

QA_PREBUILT="*"

src_install() {
	exeinto /opt/foldingathome
	doexe usr/bin/fah-client
	doexe usr/bin/fahctl

	dosym ../../opt/foldingathome/fah-client /usr/bin/fah-client
	dosym ../../opt/foldingathome/fahctl /usr/bin/fahctl

	keepdir /etc/fah-client
	keepdir /var/lib/fah-client
	keepdir /var/log/fah-client
	fowners foldingathome:foldingathome /etc/fah-client
	fowners foldingathome:foldingathome /var/lib/fah-client
	fowners foldingathome:foldingathome /var/log/fah-client

	newinitd "${FILESDIR}"/foldingathome-initd fah-client
	newconfd "${FILESDIR}"/foldingathome-confd fah-client
	systemd_dounit "${FILESDIR}"/fah-client.service

	insinto /usr/share/polkit-1/rules.d
	newins "${FILESDIR}"/10-fah-client.rules 10-fah-client.rules

	newicon usr/share/pixmaps/fahlogo.png fah-client.png
	make_desktop_entry "xdg-open https://app.foldingathome.org/" \
		"Folding@home Client" fah-client "Science;Biology;"

	dodoc usr/share/doc/fah-client/README.md
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "To run Folding@home in the background at boot:"
	elog "  OpenRC:  rc-update add fah-client default"
	elog "  systemd: systemctl enable fah-client"
	elog ""
	elog "Access the web interface at http://localhost:7396"
	elog "Or use the official web app at https://app.foldingathome.org/"
}

pkg_postrm() {
	xdg_pkg_postrm
	elog "Folding@home data files in /var/lib/fah-client were not removed."
	elog "Remove them manually if no longer needed."
}
