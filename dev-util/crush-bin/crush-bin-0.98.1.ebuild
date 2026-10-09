# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit shell-completion

MY_PN="${PN%-bin}"

DESCRIPTION="Crush, a glamourous AI coding agent for the terminal"
HOMEPAGE="https://charm.land/ https://github.com/charmbracelet/crush"
CRUSH_BASE="https://github.com/charmbracelet/crush/releases/download/v${PV}"
SRC_URI="
	amd64? (
		${CRUSH_BASE}/${MY_PN}_${PV}_Linux_x86_64.tar.gz
			-> ${P}-amd64.tar.gz
	)
	arm64? (
		${CRUSH_BASE}/${MY_PN}_${PV}_Linux_arm64.tar.gz
			-> ${P}-arm64.tar.gz
	)
"

# Functional Source License: source-available, converts to MIT two years after
# each release. Not an OSI licence today, hence the overlay-local copy in
# licenses/FSL-1.1-MIT -- ::gentoo carries no FSL entry.
LICENSE="FSL-1.1-MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

src_unpack() {
	default

	# The tarball's top-level directory embeds upstream's own arch spelling,
	# so S cannot be a plain global assignment.
	if use amd64; then
		S="${WORKDIR}/${MY_PN}_${PV}_Linux_x86_64"
	else
		S="${WORKDIR}/${MY_PN}_${PV}_Linux_arm64"
	fi
}

src_install() {
	dobin "${MY_PN}"

	# Portage compresses man pages itself, and doman rejects a page that
	# arrives already gzipped.
	gunzip manpages/"${MY_PN}".1.gz || die
	doman manpages/"${MY_PN}".1

	newbashcomp completions/"${MY_PN}".bash "${MY_PN}"
	newzshcomp completions/"${MY_PN}".zsh "_${MY_PN}"
	newfishcomp completions/"${MY_PN}".fish "${MY_PN}".fish

	dodoc README.md
}
