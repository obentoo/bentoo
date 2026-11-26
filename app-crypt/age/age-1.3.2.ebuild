# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 1.3.1-r1 ebuild, bumped ahead of ::gentoo to 1.3.2. The
# Go deps come from a vendor tarball hosted by the overlay instead of
# ::gentoo's dev.gentoo.org GOMODCACHE tarball. Drop this copy once ::gentoo
# ships >=1.3.2.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: metadata.xml - this overlay as maintainer, a
# bugs-to link added.

inherit go-module

DESCRIPTION="A simple, modern and secure encryption tool (and Go library)"
HOMEPAGE="https://github.com/FiloSottile/age"
SRC_URI="https://github.com/FiloSottile/age/archive/v${PV}.tar.gz -> ${P}.tar.gz"
# Vendored dependency tree, generated with `go mod vendor` and hosted by the
# overlay, so the build carries a checksum and needs no network.
SRC_URI+=" https://distfiles.obentoo.org/${P}-vendor.tar.xz"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64"

BDEPEND=">=dev-lang/go-1.25"

src_prepare() {
	default
	mkdir bin || die
}

src_compile() {
	ego build -ldflags "-X main.Version=${PV}" -o bin filippo.io/age/cmd/...
}

src_test() {
	ego test filippo.io/age/cmd/...
}

src_install() {
	dobin bin/*
	doman doc/*.1

	local DOCS=( README.md )
	local HTML_DOCS=( doc/*.html )
	einstalldocs
}
