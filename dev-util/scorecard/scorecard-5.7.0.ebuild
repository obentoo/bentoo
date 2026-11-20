# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="OpenSSF Scorecard: security health metrics for open source projects"
HOMEPAGE="https://scorecard.dev https://github.com/ossf/scorecard"
SRC_URI="https://github.com/ossf/scorecard/archive/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0 BSD BSD-2 ISC MIT MPL-2.0 Unlicense"
SLOT="0"
KEYWORDS="~amd64"

# Go modules are downloaded in src_unpack (upstream publishes no vendor
# tarball), so the network sandbox must be disabled. Most tests need network
# access and GitHub credentials.
RESTRICT="network-sandbox test"

BDEPEND=">=dev-lang/go-1.26.5"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	# scripts/version-ldflags reads these from git, absent in a tarball.
	local pkg=sigs.k8s.io/release-utils/version
	ego build -trimpath -tags netgo \
		-ldflags "-X ${pkg}.gitVersion=v${PV} -X ${pkg}.gitTreeState=clean" \
		-o scorecard .
}

src_install() {
	dobin scorecard
	dodoc README.md
	docinto docs
	dodoc docs/checks.md
}
