# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="Vulnerability scanner for container images, file systems, and Git repos"
HOMEPAGE="https://trivy.dev https://github.com/aquasecurity/trivy"
SRC_URI="https://github.com/aquasecurity/trivy/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" BSD BSD-2 ISC MIT MPL-2.0 Unlicense"
SLOT="0"
KEYWORDS="~amd64"

# Go modules are downloaded in src_unpack (upstream stopped publishing a vendor
# tarball after v0.55.2), so the network sandbox must be disabled. Tests need
# network/registry fixtures and are restricted.
RESTRICT="network-sandbox test"

# Go 1.27 is the floor, not a preference: pkg/x/json and the CloudFormation
# parser use encoding/json/v2, which graduated from GOEXPERIMENT to a
# default-on package in 1.27, and upstream now targets that finalized API.
BDEPEND=">=dev-lang/go-1.27.0"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	ego build \
		-ldflags="-s -X github.com/aquasecurity/trivy/pkg/version/app.ver=${PV}" \
		-o trivy ./cmd/trivy
}

src_install() {
	dobin trivy
	einstalldocs
}
