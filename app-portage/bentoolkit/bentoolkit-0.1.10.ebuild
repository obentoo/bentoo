# Copyright 2024-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="CLI tools for Bentoo Linux distribution maintainers and developers"
HOMEPAGE="https://github.com/obentoo/bentoolkit"
SRC_URI="https://github.com/obentoo/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~x86"
RESTRICT="network-sandbox"

RDEPEND="dev-vcs/git"

src_unpack() {
	default
	cd "${S}" || die
	ego mod download
}

src_compile() {
	local version_pkg="github.com/obentoo/bentoolkit/internal/common/version"
	local build_date=$(date -u '+%Y-%m-%d_%H:%M:%S')
	local ldflags="-X ${version_pkg}.Version=${PV} -X ${version_pkg}.Commit=release -X ${version_pkg}.BuildDate=${build_date}"

	ego build -ldflags "${ldflags}" -o bentoo ./cmd/bentoo
}

src_install() {
	dobin bentoo
	einstalldocs
}

pkg_postinst() {
	elog "bentoolkit has been installed."
	elog ""
	elog "Available commands:"
	elog "  bentoo overlay status  - View pending changes"
	elog "  bentoo overlay add     - Stage changes"
	elog "  bentoo overlay commit  - Commit with auto-generated message"
	elog "  bentoo overlay push    - Push to remote"
	elog ""
	elog "Configuration: ~/.config/bentoo/config.yaml"
	elog ""
	elog "Example config.yaml:"
	elog "  overlay:"
	elog "    path: /var/db/repos/bentoo"
	elog "  git:"
	elog "    user: your_username"
	elog "    email: your_email@example.com"
}
