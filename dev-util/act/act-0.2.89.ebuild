# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="run github workflows locally"
HOMEPAGE="https://nektosact.com"
SRC_URI="https://github.com/nektos/act/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 ISC MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"

# Go modules are downloaded in src_unpack (no upstream vendor tarball is
# published for act 0.2.89+), so the network sandbox must be disabled. Tests
# need network/docker fixtures and are restricted.
RESTRICT="network-sandbox test"

BDEPEND=">=dev-lang/go-1.24"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	emake VERSION="${PV}" build
}

src_install() {
	dobin dist/local/act
}
