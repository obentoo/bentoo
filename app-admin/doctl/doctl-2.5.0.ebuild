# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit edo go-module shell-completion

DESCRIPTION="A command line tool for DigitalOcean services"
HOMEPAGE="https://github.com/digitalocean/doctl"
SRC_URI="https://github.com/digitalocean/${PN}/releases/download/v${PV}/${P}-source.tar.gz"
S="${WORKDIR}"

LICENSE="Apache-2.0 MIT BSD BSD-2 ISC MPL-2.0"
SLOT="0"
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only, where ::gentoo also carries ~x86:
# the overlay baseline is amd64 (x86-64-v3), and this ebuild is a
# bump past ::gentoo, not a mirror of it.
# BENTOO-DIVERGENCE: metadata.xml - ::gentoo's file names its proxied
# maintainer; ours names this overlay's, and adds upstream bugs-to, doc and
# changelog links plus a longer description. Documentation, nothing to align.
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

# go.mod declares "go 1.26.10"; the go-module eclass floor (1.24.11) is lower.
BDEPEND="
	>=dev-lang/go-1.26.10
	test? ( dev-vcs/git )
"

src_compile() {
	LDFLAGS="-X github.com/digitalocean/doctl.Major=$(ver_cut 1)
		-X github.com/digitalocean/doctl.Minor=$(ver_cut 2)
		-X github.com/digitalocean/doctl.Patch=$(ver_cut 3-)
		-X github.com/digitalocean/doctl.Label=release"
	GOFLAGS="-v -x -mod=vendor" ego build -ldflags "$LDFLAGS" ./cmd/...

	local completion
	for completion in bash zsh fish ; do
		edo ./doctl completion ${completion} > doctl.${completion} \
			|| die "completion for ${completion} failed"
	done
}

src_test() {
	git init || die "git init failed"
	git config user.email "you@example.com" || die "git mail config failed"
	git config user.name "Your Name" || die "git user config failed"

	GOFLAGS="-v -x -mod=vendor" ego test -work ./commands/... ./do/... \
		./pkg/... ./internal/... .
}

src_install() {
	einstalldocs
	dobin doctl

	newbashcomp doctl.bash doctl
	newfishcomp doctl.fish doctl
	newzshcomp doctl.zsh _doctl
}
