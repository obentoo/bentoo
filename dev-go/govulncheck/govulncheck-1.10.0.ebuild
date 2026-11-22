# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

MY_PN="vuln"

DESCRIPTION="Reports known vulnerabilities affecting Go code, with reachability analysis"
HOMEPAGE="https://pkg.go.dev/golang.org/x/vuln/cmd/govulncheck"
SRC_URI="https://github.com/golang/vuln/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay, so the build carries a checksum and needs no network.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"
S="${WORKDIR}/${MY_PN}-${PV}"

LICENSE="BSD"
# Dependent (bundled, statically linked) Go module licenses
LICENSE+=" Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"

# Upstream publishes GitHub releases only up to v1.1.4 while tagging every
# version since; v1.8.0 is a tag with no release. Probing releases/latest here
# would pin a January 2025 version that PANICS on Go 1.27 sources, because its
# golang.org/x/tools (v0.29.0) predates the current AST. Probe the tags.
BDEPEND=">=dev-lang/go-1.26"

# The test suite compares against a live vulnerability database and needs
# network access plus fixed toolchain output.
RESTRICT="test"

# govulncheck names itself from debug.ReadBuildInfo(), which only carries a
# version when the binary was `go install`ed from the module proxy. Built from
# a tarball it reads "(devel)" and the VCS fallback finds no git checkout, so
# the scanner calls itself govulncheck@v0.0.0 -- in output people paste into
# reports. The patch short-circuits that fallback with a placeholder that
# src_prepare fills from ${PV}, so a version bump needs no patch refresh.
PATCHES=(
	"${FILESDIR}"/${PN}-report-real-version.patch
)

src_prepare() {
	default
	sed -i "s/@GENTOO_PV@/v${PV}/" internal/scan/run.go || die
	grep -q "\"v${PV}\"" internal/scan/run.go || die "scanner version not set"
}

src_compile() {
	ego build -trimpath -o govulncheck ./cmd/govulncheck
}

src_install() {
	dobin govulncheck
	einstalldocs
	dodoc doc/*.md
}
