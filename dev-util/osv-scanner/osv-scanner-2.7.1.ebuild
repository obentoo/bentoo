# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="Vulnerability scanner for open source dependencies and SBOMs"
HOMEPAGE="https://google.github.io/osv-scanner/ https://github.com/google/osv-scanner"
SRC_URI="https://github.com/google/osv-scanner/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" BSD BSD-2 ISC MIT MPL-2.0 Unlicense"
SLOT="0"
KEYWORDS="~amd64"

# Go modules are downloaded in src_unpack (upstream does not publish a vendor
# tarball), so the network sandbox must be disabled. Tests require network
# access to the OSV API and are restricted.
RESTRICT="network-sandbox test"

BDEPEND=">=dev-lang/go-1.26.4"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	# OSVVersion is baked into internal/version at the release tag, so no
	# version ldflags injection is required.
	ego build -o osv-scanner ./cmd/osv-scanner
}

src_install() {
	dobin osv-scanner
	einstalldocs
}
