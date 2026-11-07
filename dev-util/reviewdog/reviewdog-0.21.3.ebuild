# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="Posts the output of any linter as review comments, filtered to the diff"
HOMEPAGE="https://github.com/reviewdog/reviewdog"
SRC_URI="https://github.com/reviewdog/reviewdog/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 ISC MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"

BDEPEND=">=dev-lang/go-1.26"

# Go modules are downloaded in src_unpack (no vendor tarball is published for
# reviewdog 0.21.1), so the network sandbox must be disabled. The test suite
# talks to the GitHub and GitLab APIs.
RESTRICT="network-sandbox test"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	local go_ldflags=(
		-X "github.com/reviewdog/reviewdog/commands.Version=${PV}"
	)
	ego build -trimpath -ldflags "${go_ldflags[*]}" -o reviewdog ./cmd/reviewdog
}

src_install() {
	dobin reviewdog
	einstalldocs
}
