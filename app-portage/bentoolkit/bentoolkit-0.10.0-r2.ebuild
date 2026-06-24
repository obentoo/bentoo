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
IUSE="+secure kde playwright +browser +system-snapshot systemd"

# playwright and browser are two alternative backends for the same headless
# "script" version parser, so at most one may be enabled.
REQUIRED_USE="?? ( playwright browser )"

# browser? enables the chromedp backend, which drives an already-installed
# Chrome/Chromium over the DevTools Protocol (it does not download a browser).
RDEPEND="
	dev-vcs/git
	kde? ( kde-apps/kdialog )
	browser? (
		|| (
			www-client/chromium
			www-client/google-chrome
		)
	)
"

# Optional runtime backends for the `bentoo snapshot` manager. A single
# system-snapshot flag pulls the full set (btrbk/snapper engines plus
# restic/rclone cloud-ship); systemd adds timer-based scheduling. The
# binary degrades gracefully -- `bentoo snapshot detect` reports an
# actionable error naming the exact package whenever an active config
# needs an absent backend.
RDEPEND+="
	system-snapshot? (
		app-backup/btrbk
		app-backup/snapper
		app-backup/restic
		net-misc/rclone
	)
	systemd? ( sys-apps/systemd )
"

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
	# autoupdate packages) lives behind a build tag; without one the binary
	# ships only the stub that reports ErrScriptSupportNotBuilt. `playwright`
	# bundles its own browsers; `browser` (chromedp) drives the system Chrome.
	# REQUIRED_USE keeps the two mutually exclusive.
	local gotags=""
	use playwright && gotags="-tags playwright"
	use browser && gotags="-tags chromedp"

	ego build ${gotags} -ldflags "${ldflags}" -o bentoo ./cmd/bentoo
}

src_install() {
	dobin bentoo
	einstalldocs

	if use secure; then
		insinto /etc/bash/bashrc.d
		doins "${FILESDIR}"/30-bentoo-safety.bash
	fi

	if use kde; then
		# Helper de exclusão com código (chamado pelo Service Menu do Dolphin)
		exeinto /usr/libexec/bentoo
		doexe "${FILESDIR}"/bentoo-secure-delete
		# Service Menu do Dolphin/KIO (Plasma 6)
		insinto /usr/share/kio/servicemenus
		doins "${FILESDIR}"/bentoo-secure-delete.desktop
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
		elog "The headless-browser (\"script\") version parser is enabled"
		elog "(Playwright backend). It needs the Playwright browsers at runtime."
		elog "If 'bentoo overlay autoupdate' reports 'could not start Playwright',"
		elog "install them once:"
		elog "  playwright install chromium"
	fi

	if use browser; then
		elog ""
		elog "The headless-browser (\"script\") version parser is enabled"
		elog "(chromedp backend). It drives an already-installed Chrome/Chromium"
		elog "over the DevTools Protocol -- no extra download is needed."
		elog "If autoupdate reports 'could not launch headless Chrome', make sure"
		elog "www-client/chromium or www-client/google-chrome is installed and"
		elog "reachable on PATH (chromedp auto-detects chromium/google-chrome*)."
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

	if use kde; then
		elog ""
		elog "A Dolphin service menu 'Excluir permanentemente (código Bentoo)'"
		elog "was installed. It asks for a one-time code via kdialog before an"
		elog "irreversible delete. Note: KDE/Dolphin use KIO and never call rm,"
		elog "so this only covers the explicit menu action -- the native Delete"
		elog "and Move-to-Trash entries are unaffected."
		elog "To protect arbitrary critical paths against GUI deletion, use the"
		elog "kernel immutable bit: chattr +i <path> (undo with chattr -i)."
	fi
}
