# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Cline, an autonomous AI coding agent for the terminal"
HOMEPAGE="https://cline.bot/ https://github.com/cline/cline"
# The GitHub releases only carry the macOS/Windows desktop app, so the Linux
# build is fetched from the npm registry instead. Upstream splits it per
# platform behind optionalDependencies of the "cline" wrapper package; those
# per-platform packages are the actual payload and are what is pinned here.
CLINE_BASE="https://registry.npmjs.org/@cline"
SRC_URI="
	amd64? (
		${CLINE_BASE}/cli-linux-x64/-/cli-linux-x64-${PV}.tgz
			-> ${P}-amd64.tgz
	)
"
S="${WORKDIR}/package"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_install() {
	# "cline" resolves cline-hub/ and extensions/ relative to its own location,
	# so the tree is installed whole rather than split across the filesystem.
	insinto /opt/cline-bin
	doins -r bin cline-hub extensions

	# npm marks every file in the tarball executable, and doins drops the bit
	# from all of them. Only the ELF binary actually needs it back.
	fperms 0755 /opt/cline-bin/bin/cline

	dosym -r /opt/cline-bin/bin/cline /opt/bin/cline
}
