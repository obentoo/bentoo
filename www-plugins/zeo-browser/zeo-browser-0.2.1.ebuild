# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Firefox sidebar that shows and drives the Zeo agent thread"
HOMEPAGE="https://github.com/zeo-workspace/zeo-browser"
# The XPI is built reproducibly from the release tag (`npm ci && npm run build`
# -> dist/zeo-browser-firefox.zip, renamed .xpi) and is unsigned: a
# source-built www-client/firefox accepts it in the system scope below.
SRC_URI="https://github.com/zeo-workspace/zeo-browser/releases/download/v${PV}/zeo-browser-firefox-${PV}.xpi"
S="${WORKDIR}"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"

# Zeo up to 0.5.0_p20261014-r1 installed this same file itself under USE
# browser-extension. A soft blocker lets Portage allow the overlap while it
# replaces that Zeo, which pulls this package in from -r2 on.
RDEPEND="!<app-editors/zeo-0.5.0_p20261014-r2[browser-extension]"

src_unpack() {
	# An .xpi is installed as is, never unpacked.
	:
}

src_install() {
	# System scope, keyed by Firefox's application ID: every profile loads it.
	insinto "/usr/$(get_libdir)/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
	newins "${DISTDIR}/zeo-browser-firefox-${PV}.xpi" zeo-browser@zeo.dev.xpi
}

pkg_postinst() {
	elog "The add-on reaches Zeo through the native-messaging host zeo-browser-host,"
	elog "which app-editors/zeo installs with USE browser-extension. Restart Firefox"
	elog "to load it. A Firefox that enforces add-on signing (www-client/firefox-bin)"
	elog "will not load this unsigned build."
}
