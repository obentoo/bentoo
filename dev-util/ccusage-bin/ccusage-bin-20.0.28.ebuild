# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN="${PN%-bin}"

DESCRIPTION="ccusage, a token usage and cost analyser for Claude Code and other agents"
HOMEPAGE="https://ccusage.com/ https://github.com/ccusage/ccusage"
# GitHub publishes no Linux asset. Upstream distributes through npm, where the
# main "ccusage" package is a 20 KB wrapper that refuses to run on its own --
# it prints "native binary is not available" and exits 1. The real payload is
# the per-platform package pinned below.
CCUSAGE_BASE="https://registry.npmjs.org/@${MY_PN}"
SRC_URI="
	amd64? (
		${CCUSAGE_BASE}/${MY_PN}-linux-x64/-/${MY_PN}-linux-x64-${PV}.tgz
			-> ${P}-amd64.tgz
	)
	arm64? (
		${CCUSAGE_BASE}/${MY_PN}-linux-arm64/-/${MY_PN}-linux-arm64-${PV}.tgz
			-> ${P}-arm64.tgz
	)
"
S="${WORKDIR}/package"

LICENSE="MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_install() {
	# The binary is static-pie and self-contained: it needs neither Node nor
	# the JavaScript wrapper, so it goes straight into /usr/bin rather than
	# under /opt with a launcher. npm ships it mode 0644; doexe restores the
	# executable bit.
	exeinto /usr/bin
	doexe bin/${MY_PN}
}
