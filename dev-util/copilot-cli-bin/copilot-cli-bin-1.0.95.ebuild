# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="GitHub Copilot CLI, GitHub's terminal-native AI coding agent"
HOMEPAGE="https://github.com/github/copilot-cli"
COPILOT_BASE="https://github.com/github/copilot-cli/releases/download/v${PV}"
# Upstream ships two parallel trains from the same repository: "vX.Y.Z-N" tags
# are pre-releases (respin counter N), and only the bare "vX.Y.Z" tag is the
# stable release. Package the bare tag -- /releases/latest returns it and skips
# the -N ones, which is why the autoupdate record probes that endpoint.
SRC_URI="
	amd64? (
		${COPILOT_BASE}/copilot-linux-x64.tar.gz
			-> ${P}-amd64.tar.gz
	)
	arm64? (
		${COPILOT_BASE}/copilot-linux-arm64.tar.gz
			-> ${P}-arm64.tar.gz
	)
"
S="${WORKDIR}"

# Proprietary: the GitHub Copilot CLI License, shipped as LICENSE.md upstream.
# The repository carries no source code at all -- only that licence, a README,
# a changelog and an installer script -- so a binary package is the only
# packaging possible here, not a shortcut taken to avoid a build.
LICENSE="github-copilot-cli"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_install() {
	exeinto /opt/copilot-cli
	doexe copilot

	dosym -r /opt/copilot-cli/copilot /opt/bin/copilot
}
