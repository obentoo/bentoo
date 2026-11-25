# Copyright 2024-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit go-module

DESCRIPTION="CLI tools for Bentoo Linux distribution maintainers and developers"
HOMEPAGE="https://github.com/obentoo/bentoolkit"
# The vendor tarball is the tag's `go mod vendor`, published with each
# release (signed; see "Release assets" in upstream's docs/development.md), so
# the build needs no network access.
SRC_URI="
	https://github.com/obentoo/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/obentoo/${PN}/releases/download/v${PV}/${P}-vendor.tar.xz
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"
# The languages the release translates, as L10N names; po/ spells them with
# an underscore (pt-BR -> po/pt_BR.po).
L10N_LOCALES=( es pt-BR ru zh-CN )
IUSE="+secure kde +browser +system-snapshot systemd ${L10N_LOCALES[*]/#/l10n_}"
# go.mod declares go 1.27.0 with toolchain go1.27.4, but the Go that builds
# this package decides the standard library it links: 1.27.3 carries
# GO-2026-6859 (net/http), fixed in 1.27.4.
BDEPEND=">=dev-lang/go-1.27.4"
# msgfmt compiles the catalogs of the enabled languages.
BDEPEND+="
	l10n_es? ( sys-devel/gettext )
	l10n_pt-BR? ( sys-devel/gettext )
	l10n_ru? ( sys-devel/gettext )
	l10n_zh-CN? ( sys-devel/gettext )
"

# browser? enables the chromedp backend, which drives an already-installed
# Chrome/Chromium over the DevTools Protocol (it does not download a browser).
# bwrap: since 0.46.0 the host build gates of overlay autoupdate, validate
# and compare run `ebuild` inside a bubblewrap sandbox, and refuse to build
# (every gate SKIPPED) when it is missing.
RDEPEND="
	dev-vcs/git
	sys-apps/bubblewrap
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
# The safety guards (USE=secure, USE=kde) translate their messages through
# the gettext command.
RDEPEND+="
	l10n_es? ( sys-devel/gettext )
	l10n_pt-BR? ( sys-devel/gettext )
	l10n_ru? ( sys-devel/gettext )
	l10n_zh-CN? ( sys-devel/gettext )
"

src_compile() {
	local version_pkg="github.com/obentoo/bentoolkit/internal/common/version"
	local build_date=$(date -u '+%Y-%m-%d_%H:%M:%S')
	local ldflags="-X ${version_pkg}.Version=${PV}"
	ldflags+=" -X ${version_pkg}.Commit=release"
	ldflags+=" -X ${version_pkg}.BuildDate=${build_date}"
	ldflags+=" -X github.com/obentoo/bentoolkit/internal/common/i18n.LocaleDir=${EPREFIX}/usr/share/locale"

	# The "script" version parser (headless-browser backend used by some
	# autoupdate packages) lives behind a build tag; without one the binary
	# ships only the stub that reports ErrScriptSupportNotBuilt. `browser`
	# (chromedp) drives the system Chrome.
	local gotags=""
	use browser && gotags="-tags chromedp"

	ego build ${gotags} -ldflags "${ldflags}" -o bentoo ./cmd/bentoo

	local l po
	for l in "${L10N_LOCALES[@]}"; do
		use "l10n_${l}" || continue
		po=${l/-/_}
		mkdir -p "locale/${po}/LC_MESSAGES" || die
		msgfmt --check -o "locale/${po}/LC_MESSAGES/bentoolkit.mo" "po/${po}.po" ||
			die "msgfmt failed for po/${po}.po"
	done

	if use kde; then
		# The Dolphin service menu, with every release translation merged in
		# when msgfmt is here (an l10n flag is set), English otherwise.
		local desktop=misc/safety/bentoo-secure-delete.desktop.in
		if [[ -d locale ]]; then
			msgfmt --desktop --template="${desktop}" -d po \
				-o bentoo-secure-delete.desktop || die "msgfmt --desktop failed"
		else
			cp "${desktop}" bentoo-secure-delete.desktop || die
		fi
		sed -i "s|@LIBEXECDIR@|${EPREFIX}/usr/libexec/bentoo|g" bentoo-secure-delete.desktop || die
	fi
}

src_install() {
	dobin bentoo
	einstalldocs

	if [[ -d locale ]]; then
		insinto /usr/share
		doins -r locale
	fi

	# The safety guards ship in the release tarball (misc/safety/), see
	# upstream's docs/safety.md.
	if use secure; then
		insinto /etc/bash/bashrc.d
		doins misc/safety/30-bentoo-safety.bash
	fi

	if use kde; then
		# Secure deletion helper (called by the Dolphin Service Menu)
		exeinto /usr/libexec/bentoo
		doexe misc/safety/bentoo-secure-delete
		# Dolphin/KIO Service Menu entry (Plasma 6)
		insinto /usr/share/kio/servicemenus
		doins bentoo-secure-delete.desktop
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
		elog "A Dolphin service menu 'Delete permanently (Bentoo code)'"
		elog "was installed. It asks for a one-time code via kdialog before an"
		elog "irreversible delete. Note: KDE/Dolphin use KIO and never call rm,"
		elog "so this only covers the explicit menu action -- the native Delete"
		elog "and Move-to-Trash entries are unaffected."
		elog "To protect arbitrary critical paths against GUI deletion, use the"
		elog "kernel immutable bit: chattr +i <path> (undo with chattr -i)."
	fi
}
