# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module shell-completion

DESCRIPTION="A SAST tool for detecting and preventing hardcoded secrets in git repos"
HOMEPAGE="https://github.com/gitleaks/gitleaks"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/gitleaks/gitleaks.git"
else
	SRC_URI="https://github.com/gitleaks/gitleaks/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm64"
	S="${WORKDIR}/${PN}-${PV}"
fi

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 ISC MPL-2.0"
SLOT="0"

# Go modules are downloaded in src_unpack (no upstream vendor tarball is
# published for gitleaks), so the network sandbox must be disabled. Tests
# need network/git fixtures and are restricted.
RESTRICT="network-sandbox test"

BDEPEND=">=dev-lang/go-1.24"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	local version_pkg="github.com/zricethezav/gitleaks/v8/version"
	local go_ldflags=(
		-X "${version_pkg}.Version=${PV}"
	)
	ego build -o gitleaks -ldflags "${go_ldflags[*]}" .

	# gitleaks uses cobra, which ships a built-in completion command.
	local shell
	for shell in bash zsh fish; do
		./gitleaks completion "${shell}" > "${PN}.${shell}" || die
	done
}

src_install() {
	dobin gitleaks

	newbashcomp "${PN}.bash" "${PN}"
	newzshcomp "${PN}.zsh" "_${PN}"
	dofishcomp "${PN}.fish"

	einstalldocs
}
