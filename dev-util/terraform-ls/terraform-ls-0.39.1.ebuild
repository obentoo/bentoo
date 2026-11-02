# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module optfeature

DESCRIPTION="Terraform Language Server"
HOMEPAGE="https://github.com/hashicorp/terraform-ls"
SRC_URI="https://github.com/hashicorp/terraform-ls/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay (see scripts/go-vendor.sh). It carries a checksum in the Manifest, so
# the build needs no network and stays inside the sandbox.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

# terraform-ls itself is MPL-2.0 (unlike terraform, it was never relicensed
# under BUSL).
LICENSE="MPL-2.0"
# Dependent (bundled, statically linked) Go module licenses, surveyed from the
# modules `go version -m` lists for the built binary.
LICENSE+=" Apache-2.0 BSD ISC MIT"
SLOT="0"
KEYWORDS="~amd64"

BDEPEND=">=dev-lang/go-1.26.8"

# Upstream release builds embed the schemas of every official and partner
# provider, produced by `go generate ./internal/schemas`, which downloads
# terraform plus hundreds of providers. That cannot run in the sandbox, so this
# build embeds none: completion for provider blocks comes from the schemas of
# initialized modules (`terraform init`), read through the terraform CLI.
# The Algolia registry-search keys upstream injects with -X are secrets of their
# CI and stay empty, which disables registry module search.

src_compile() {
	# The version is embedded from version/VERSION by go:embed.
	ego build -trimpath -o terraform-ls .
}

src_test() {
	ego test ./...
}

src_install() {
	dobin terraform-ls
	dodoc README.md CHANGELOG.md
}

pkg_postinst() {
	optfeature "provider schemas, validation and formatting of initialized modules" app-admin/terraform
}
