# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Local, extensible AI agent that executes, edits and tests code, with MCP support"
HOMEPAGE="https://goose-docs.ai/ https://github.com/aaif-goose/goose"
# Upstream moved from block/goose to aaif-goose/goose; the old path only
# resolves through a GitHub 301 that can be withdrawn at any time, so pin
# the canonical org here.
GOOSE_BASE="https://github.com/aaif-goose/goose/releases/download/v${PV}"
SRC_URI="
	amd64? (
		${GOOSE_BASE}/goose-x86_64-unknown-linux-gnu.tar.bz2
			-> ${P}-amd64.tar.bz2
	)
"
S="${WORKDIR}"

# Upstream ships only Apache-2.0-licensed release archives; verified via the
# GitHub license API. Only the plain glibc CLI tarball is packaged here --
# the -vulkan and -musl CLI variants, and the separate Desktop app
# (Goose.zip / .rpm / .deb), are out of scope for this ebuild.
LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_install() {
	exeinto /opt/goose-bin
	doexe goose

	dosym -r /opt/goose-bin/goose /opt/bin/goose
}
