# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# PREBUILT PACKAGING NOTES -- READ BEFORE A VERSION BUMP.
#
# 1) Why a -bin at all, when ::gentoo already has sys-apps/uutils-coreutils:
#    the from-source ebuild pulls ~400 crates and a Rust toolchain.  Upstream
#    publishes official binaries for every release, so users who only want the
#    utilities (containers, edge boxes, machines with no Rust)
#    should not have to compile them.  This package installs exactly the same
#    file layout as the from-source one, so the two are interchangeable.
#
# 2) Why the glibc build rather than the static musl one: a statically
#    linked musl binary resolves users and groups through musl's own minimal
#    NSS -- it reads /etc/passwd and /etc/group directly and cannot consult
#    nsswitch.conf modules (LDAP, SSSD, systemd-userdb).  That would silently
#    change the output of `uu-ls -l`, `uu-id` and `uu-chown` on hosts with
#    networked accounts.  Verified glibc floor (objdump -T):
#       x86_64-unknown-linux-gnu -> GLIBC_2.39
#    Re-check it on a bump; if the floor ever exceeds the oldest glibc in
#    ::gentoo, switch over to the musl tarball.
#
# 3) Where the applet list, the man pages and the completions come from:
#    up to 0.11.0 upstream published an architecture independent docs.tar.zst
#    next to the binaries, and this ebuild derived everything from it.  0.12.0
#    dropped that asset; instead every release tarball now ships a second
#    binary, "uudoc", which prints a man page or a completion script for any
#    applet on stdout.  So the payload itself is the source of truth here, and
#    `coreutils --list` is the applet list.  Consequence: the build host must
#    be able to EXECUTE the target binary, which rules out cross-arch builds;
#    src_install dies with an explicit message when that is the case.  One
#    name in --list is not installed: "stdbuf" needs libstdbuf.so in libexec,
#    which the release tarballs do not ship.
#
# 4) Why the completion files are rewritten with sed:
#    upstream generates them for the unprefixed command name ("#compdef ls",
#    "complete -F _ls ... ls") and merely renames the file to uu-ls.  That
#    registers the completion against GNU ls instead of uu-ls.  The seds below
#    retarget them at the installed name.  This is a deliberate improvement
#    over upstream's own install rule, not an oversight.
#
# 5) l10n: translations live in the source tree, not in the binary tarballs.
#    Release builds look them up at <prefix>/share/locales/<applet>, i.e. the
#    very path the source ebuild installs to -- verified at runtime by running
#    the shipped binary against a synthetic prefix.  en-US is compiled into the
#    binary, so only the extra locales are installed.  0.10.0 ships fr-FR only.

inherit bash-completion-r1 optfeature

MY_PN="${PN%-bin}"
MY_BASE="https://github.com/uutils/coreutils/releases/download/${PV}"

DESCRIPTION="GNU coreutils rewritten in Rust (prebuilt upstream binaries)"
HOMEPAGE="https://uutils.github.io/coreutils/ https://github.com/uutils/coreutils"

SRC_URI="
	amd64? (
		elibc_glibc? ( ${MY_BASE}/coreutils-${PV}-x86_64-unknown-linux-gnu.tar.gz )
		elibc_musl? ( ${MY_BASE}/coreutils-${PV}-x86_64-unknown-linux-musl.tar.gz )
	)
	l10n_fr? (
		https://github.com/uutils/coreutils/archive/refs/tags/${PV}.tar.gz
			-> ${MY_PN}-${PV}.tar.gz
	)
"
S="${WORKDIR}"

LICENSE="MIT"
# Dependent crate licenses, statically linked into the payload.  Kept in sync
# with the from-source ebuild -- regenerate with pycargoebuild on a bump.
LICENSE+="
	Apache-2.0 BSD-2 BSD CC0-1.0 ISC MIT MPL-2.0 Unicode-3.0 ZLIB
"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="l10n_fr"

RDEPEND="!sys-apps/uutils-coreutils"

RESTRICT="strip"
QA_PREBUILT="usr/bin/uu-coreutils"

src_install() {
	local target
	if use amd64 ; then
		target=x86_64-unknown-linux-$(usex elibc_musl musl gnu)
	else
		die "no upstream binary for this arch; use sys-apps/uutils-coreutils instead"
	fi

	local payload="${WORKDIR}/coreutils-${PV}-${target}"

	newbin "${payload}/coreutils" uu-coreutils
	dodoc "${payload}"/README.md

	# See note 3: the payload reports its own applet list, and the uudoc
	# binary shipped beside it renders the documentation.
	local uudoc="${payload}/uudoc"
	"${payload}/coreutils" --list > "${T}/applets" ||
		die "cannot execute the ${target} payload on this host; cross-arch builds must use sys-apps/uutils-coreutils from source"

	local progs=() prog
	while read -r prog ; do
		[[ ${prog} == coreutils || ${prog} == stdbuf ]] && continue
		progs+=( "${prog}" )
	done < "${T}/applets"
	[[ ${#progs[@]} -ge 100 ]] ||
		die "only ${#progs[@]} applets reported by the payload -- layout changed?"

	# The list already contains `[`, which has its own man page.
	for prog in "${progs[@]}" ; do
		dosym uu-coreutils /usr/bin/"uu-${prog}"
	done

	"${uudoc}" manpage coreutils > "${T}/uu-coreutils.1" || die
	doman "${T}/uu-coreutils.1"
	for prog in "${progs[@]}" ; do
		"${uudoc}" manpage "${prog}" > "${T}/uu-${prog}.1" || die
		doman "${T}/uu-${prog}.1"
	done

	# See note 4: retarget the completions at the uu- prefixed command.
	local esc
	for prog in "${progs[@]}" ; do
		# `[` is a regex metacharacter; escape it for the seds below.
		esc=${prog//\[/\\[}

		"${uudoc}" completion "${prog}" bash > "${T}/raw" || die
		sed -e "s/ ${esc}\$/ uu-${prog}/" \
			"${T}/raw" > "${T}/uu-${prog}" || die
		newbashcomp "${T}/uu-${prog}" "uu-${prog}"

		"${uudoc}" completion "${prog}" zsh > "${T}/raw" || die
		sed -e "s/^#compdef ${esc}\$/#compdef uu-${prog}/" \
			-e "s/^\(\s*compdef _${esc}\) ${esc}\$/\1 uu-${prog}/" \
			"${T}/raw" > "${T}/_uu-${prog}" || die
		insinto /usr/share/zsh/site-functions
		doins "${T}/_uu-${prog}"

		"${uudoc}" completion "${prog}" fish > "${T}/raw" || die
		sed -e "s/^complete -c ${esc}\b/complete -c uu-${prog}/" \
			"${T}/raw" > "${T}/uu-${prog}.fish" || die
		insinto /usr/share/fish/vendor_completions.d
		doins "${T}/uu-${prog}.fish"
	done

	# See note 5.  uucore holds the strings shared by every applet; the rest
	# are per applet, and only the applets this binary actually carries are
	# installed (the source tree also has locales for stdbuf and runcon).
	if use l10n_fr ; then
		local dir
		for prog in "${progs[@]}" uucore ; do
			dir="${WORKDIR}/coreutils-${PV}/src/uu/${prog}/locales"
			[[ ${prog} == uucore ]] &&
				dir="${WORKDIR}/coreutils-${PV}/src/uucore/locales"
			[[ -f ${dir}/fr-FR.ftl ]] || continue
			insinto "/usr/share/locales/${prog}"
			doins "${dir}"/fr-FR.ftl
		done
	fi
}

pkg_postinst() {
	elog "Every utility is installed with an 'uu-' prefix (uu-ls, uu-cp, ...)"
	elog "so this package does not shadow sys-apps/coreutils.  The multicall"
	elog "binary itself is /usr/bin/uu-coreutils; run 'uu-coreutils --list'"
	elog "for the full set of applets."
	elog
	elog "'stdbuf' is not available here: it needs a helper library that"
	elog "upstream does not ship in the release tarballs.  Build"
	elog "sys-apps/uutils-coreutils from source if you need it."

	optfeature "shell completions" app-shells/bash-completion
}
