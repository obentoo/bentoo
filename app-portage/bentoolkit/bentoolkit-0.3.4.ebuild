# Copyright 2024-2026 Gentoo Authors
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
IUSE="+secure +playwright"

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

	# The "script" version parser (headless-browser backend used by some
	# autoupdate packages) lives behind the `playwright` build tag; without it
	# the binary ships only the stub that reports ErrScriptSupportNotBuilt.
	local gotags=""
	use playwright && gotags="-tags playwright"

	ego build ${gotags} -ldflags "${ldflags}" -o bentoo ./cmd/bentoo
}

src_install() {
	dobin bentoo
	einstalldocs

	if use secure; then
		insinto /etc/bash/bashrc.d
		doins "${FILESDIR}"/30-bentoo-safety.bash
	fi
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

	if use playwright; then
		elog ""
		elog "The headless-browser (\"script\") version parser is enabled."
		elog "It needs the Playwright browsers at runtime. If 'bentoo overlay"
		elog "autoupdate' reports 'could not start Playwright', install them once:"
		elog "  playwright install chromium"
	fi

	if use secure; then
		elog ""
		elog "Shell safety guards have been installed to:"
		elog "  /etc/bash/bashrc.d/30-bentoo-safety.bash"
		elog "They add a confirmation delay/block to destructive commands"
		elog "(rm -rf, reboot, poweroff, etc.) in interactive shells."
		elog "To bypass them consciously for a single command, prefix with:"
		elog "  BENTOO_NO_GUARD=1"
	fi
}
