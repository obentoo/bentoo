# Copyright 2018-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
inherit go-env go-module

MY_PV=${PV/_/-}

DESCRIPTION="Multi-container orchestration for Docker"
HOMEPAGE="https://github.com/docker/compose"
SRC_URI="https://github.com/docker/compose/archive/v${MY_PV}.tar.gz -> ${P}.gh.tar.gz"

S="${WORKDIR}/compose-${MY_PV}"

LICENSE="Apache-2.0"
SLOT="5"
KEYWORDS="~amd64 ~arm64"

BDEPEND=">=dev-lang/go-1.24.9"

RDEPEND="|| (
	app-containers/docker
	app-containers/podman[wrapper(+)]
)"

# Network access required for Go module fetching
PROPERTIES="test_network"
RESTRICT="network-sandbox strip"

src_unpack() {
	default
	go-env_set_compile_environment
}

src_prepare() {
	default

	# Set Go environment for module handling
	export GO111MODULE=on
	export GOPROXY="https://proxy.golang.org,direct"
	export GOSUMDB="sum.golang.org"
	export GOFLAGS="-buildvcs=false"

	# Download and vendor Go modules
	einfo "Downloading Go modules..."
	go mod download -x || die "Failed to download Go modules"
	go mod verify || die "Failed to verify Go modules"
	go mod vendor || die "Failed to vendor Go modules"

	# Do not strip binaries (handled by Portage)
	sed -i -e 's/-s -w//' Makefile || die
}

src_configure() {
	export CGO_ENABLED=1
	export CGO_CFLAGS="${CFLAGS}"
	export CGO_CPPFLAGS="${CPPFLAGS}"
	export CGO_CXXFLAGS="${CXXFLAGS}"
	export CGO_LDFLAGS="${LDFLAGS}"
	export GOFLAGS="${GOFLAGS} -mod=vendor"
}

src_compile() {
	export GOFLAGS="${GOFLAGS} -mod=vendor"
	emake VERSION=v${PV} GOFLAGS="-buildmode=pie -mod=vendor ${GOFLAGS}"
}

src_test() {
	export GOFLAGS="${GOFLAGS} -mod=vendor"
	emake test
}

src_install() {
	exeinto /usr/libexec/docker/cli-plugins
	doexe bin/build/docker-compose
	dodoc README.md
}

pkg_postinst() {
	ewarn
	ewarn "Docker Compose 5.x is a major release with breaking changes:"
	ewarn
	ewarn "  - Internal buildkit builder has been removed"
	ewarn "  - Build operations are now delegated to Docker Bake"
	ewarn "  - Compose can now be used as an SDK for third-party integration"
	ewarn
	ewarn "Use 'docker compose' from the command line."
	ewarn
	elog "If you need to keep 2.x around, run:"
	elog "  emerge --noreplace docker-compose:2"
	ewarn
}
