# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Imported from ::gentoo (last commit before the 2026-11-05 treeclean,
# 00ba5be08a^) because bentoo still ships www-client/chromium, which needs
# this launcher. Unchanged except KEYWORDS (amd64 only, as chromium here).

DESCRIPTION="Common configuration files for Chromium slots"
HOMEPAGE="https://wiki.gentoo.org/wiki/Project:Chromium/"
S="${WORKDIR}"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64"
RESTRICT="test" # There is no code, only Zuul.

# Non-slotted Chromium will conflict
RDEPEND="!www-client/chromium:0"

src_unpack() {
	:
}

src_configure() {
	:
}

src_compile() {
	sed -e "s:/usr/lib/:/usr/$(get_libdir)/:g" "${FILESDIR}/chromium-launcher.sh" \
		> chromium-launcher.sh || die
}

src_install() {
	exeinto /usr/libexec/chromium
	doexe chromium-launcher.sh

	insinto /etc/chromium
	newins "${FILESDIR}/chromium.default" default
}
