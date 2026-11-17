# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="opencode, a provider-agnostic AI coding agent for the terminal"
HOMEPAGE="https://opencode.ai/ https://github.com/anomalyco/opencode"
OPENCODE_BASE="https://github.com/anomalyco/opencode/releases/download/v${PV}"
# Upstream ships three Linux CLI flavours per arch -- glibc, -musl and
# -baseline (for CPUs without the newer instruction sets) -- plus a wholly
# separate desktop app (opencode-desktop-*.deb/.rpm/.AppImage). Only the plain
# glibc CLI is packaged here; the desktop app is a different product.
SRC_URI="
	amd64? (
		${OPENCODE_BASE}/opencode-linux-x64.tar.gz
			-> ${P}-amd64.tar.gz
	)
"
S="${WORKDIR}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_install() {
	exeinto /opt/opencode-bin
	doexe opencode

	dosym -r /opt/opencode-bin/opencode /opt/bin/opencode
}
