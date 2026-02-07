# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake desktop go-env go-module systemd xdg-utils

MY_PN="${PN/-mail/}"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Serves Proton Mail to IMAP/SMTP clients"
HOMEPAGE="https://proton.me/mail/bridge https://github.com/ProtonMail/proton-bridge/"
SRC_URI="https://github.com/ProtonMail/${MY_PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}"/${MY_P}

LICENSE="GPL-3+ Apache-2.0 BSD BSD-2 ISC LGPL-3+ MIT MPL-2.0 Unlicense"
SLOT="0"
KEYWORDS="~amd64"
IUSE="gui"

# Tests require Internet access and we need network access for Go modules
PROPERTIES="test_network"
RESTRICT="network-sandbox test strip"

# Add network dependencies for Go module fetching
BDEPEND="
	>=dev-lang/go-1.21
	net-misc/wget
	net-misc/curl
	dev-vcs/git
"

RDEPEND="
	app-crypt/libsecret
	gui? (
		>=dev-libs/protobuf-21.12:=
		dev-libs/re2:=
		>=dev-libs/sentry-native-0.6.5-r1
		dev-qt/qtbase:6=[gui,icu,widgets]
		dev-qt/qtdeclarative:6=[widgets]
		dev-qt/qtsvg:6=
		media-libs/mesa
		net-libs/grpc:=
	)
"
DEPEND="${RDEPEND}"

PATCHES=(
	"${FILESDIR}"/${PN}-3.15.1-gui_gentoo.patch
)

# $S is there for bug 957684
DOCS=( "${S}"/{README,Changelog}.md )

src_unpack() {
	default
	go-env_set_compile_environment
}

src_prepare() {
	xdg_environment_reset
	default
	
	# Initialize Go modules and download dependencies
	einfo "Initializing Go modules and downloading dependencies..."
	
	# Set Go environment variables for proper module handling
	export GO111MODULE=on
	export GOPROXY="https://proxy.golang.org,direct"
	export GOSUMDB="sum.golang.org"
	export GOFLAGS="-buildvcs=false"
	
	# Download and verify Go modules
	go mod download -x || die "Failed to download Go modules"
	go mod verify || die "Failed to verify Go modules"
	
	# Vendor the dependencies locally for build reproducibility
	go mod vendor || die "Failed to vendor Go modules"
	
	if use gui; then
		# prepare desktop file
		local desktopFilePath="${S}"/dist/${MY_PN}.desktop
		sed -i 's/protonmail/proton-mail/g' ${desktopFilePath} || die
		sed -i 's/Exec=proton-mail-bridge/Exec=proton-mail-bridge-gui/g' ${desktopFilePath} || die

		# build GUI
		local PATCHES=()
		BUILD_DIR="${WORKDIR}"/gui_build \
			CMAKE_USE_DIR="${S}"/internal/frontend/bridge-gui/bridge-gui \
			cmake_src_prepare
	fi
}

src_configure() {
	# Set Go build environment
	export CGO_ENABLED=1
	export CGO_CFLAGS="${CFLAGS}"
	export CGO_CPPFLAGS="${CPPFLAGS}"
	export CGO_CXXFLAGS="${CXXFLAGS}"
	export CGO_LDFLAGS="${LDFLAGS}"
	
	# Use vendored modules for build reproducibility
	export GOFLAGS="${GOFLAGS} -mod=vendor"
	
	if use gui; then
		local mycmakeargs=(
			-DBRIDGE_APP_FULL_NAME="Proton Mail Bridge"
			-DBRIDGE_APP_VERSION="${PV}+git"
			-DBRIDGE_REPO_ROOT="${S}"
			-DBRIDGE_TAG="NOTAG"
			-DBRIDGE_VENDOR="Gentoo Linux"
			-DCMAKE_DISABLE_PRECOMPILE_HEADERS=OFF
			-Dsentry_DIR="${S}/internal/sentry"
		)
		BUILD_DIR="${WORKDIR}"/gui_build \
			CMAKE_USE_DIR="${S}"/internal/frontend/bridge-gui/bridge-gui \
			cmake_src_configure
	fi
}

src_compile() {
	# Ensure Go modules are available during compilation
	export GOFLAGS="${GOFLAGS} -mod=vendor"
	
	# Build with proper Go flags for Gentoo
	emake -Onone \
		GOFLAGS="-buildmode=pie -mod=vendor ${GOFLAGS}" \
		build-nogui

	if use gui; then
		BUILD_DIR="${WORKDIR}"/gui_build \
			CMAKE_USE_DIR="${S}"/internal/frontend/bridge-gui/bridge-gui \
			cmake_src_compile
	fi
}

src_test() {
	# Use vendored modules for testing
	export GOFLAGS="${GOFLAGS} -mod=vendor"
	emake -Onone test
}

src_install() {
	exeinto /usr/bin
	newexe bridge ${PN}

	if use gui; then
		BUILD_DIR="${WORKDIR}"/gui_build \
			CMAKE_USE_DIR="${S}"/internal/frontend/bridge-gui/bridge-gui \
			cmake_src_install
		mv "${ED}"/usr/bin/bridge-gui "${ED}"/usr/bin/${PN}-gui || die
		newicon {"${S}"/dist/bridge,${PN}}.svg
		newmenu {dist/${MY_PN},${PN}}.desktop
	fi

	systemd_newuserunit "${FILESDIR}"/${PN}.service-r1 ${PN}.service

	einstalldocs
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update
	
	elog "Proton Mail Bridge has been installed."
	elog "Go dependencies were fetched during build process."
	elog ""
	elog "To start the service:"
	elog "  systemctl --user enable --now proton-mail-bridge.service"
	elog ""
	if use gui; then
		elog "GUI version is available as: proton-mail-bridge-gui"
	fi
	elog "Command-line version is available as: proton-mail-bridge"
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}
