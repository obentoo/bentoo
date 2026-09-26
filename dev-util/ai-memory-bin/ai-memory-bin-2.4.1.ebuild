# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit shell-completion systemd tmpfiles toolchain-funcs

# Upstream names every path, file and binary "ai-memory"; only the Portage
# package carries the -bin suffix.  MY_PN keeps the two apart so this ebuild
# stays a line-by-line mirror of dev-util/ai-memory.
MY_PN="${PN%-bin}"

DESCRIPTION="Local-first long-term memory MCP server for AI coding agents (upstream prebuilt)"
HOMEPAGE="https://github.com/akitaonrails/ai-memory"

# Upstream publishes one Linux asset per architecture at each tag, so both
# ~amd64 and ~arm64 are real builds rather than an untested keyword.  Neither
# tarball has a top-level directory -- they extract straight into ${WORKDIR}.
SRC_URI="
	amd64? (
		https://github.com/akitaonrails/ai-memory/releases/download/v${PV}/ai-memory-linux-x86_64.tar.gz
			-> ${P}-amd64.tar.gz
	)
	arm64? (
		https://github.com/akitaonrails/ai-memory/releases/download/v${PV}/ai-memory-linux-aarch64.tar.gz
			-> ${P}-arm64.tar.gz
	)
"
S="${WORKDIR}"

# License for the package itself
LICENSE="MIT"
# Every Rust crate dev-util/ai-memory compiles is linked into this binary, so
# the same license set applies to what is actually distributed here. Note the
# binary is NOT statically linked as a whole -- it needs libc, libm, libgcc_s
# and libz from the system (see RDEPEND); it is the crate graph that is
# internal to it.
LICENSE+="
	Apache-2.0 BSD CC0-1.0 CDLA-Permissive-2.0 ISC MIT MPL-2.0
	Unicode-3.0 ZLIB
"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"

# The from-source ebuild has no USE flag for the LLM crate's local-embeddings
# feature and neither can this one: these ARE the release binaries that feature
# is default-on in, and a prebuilt exposes no build knobs at all.  It is
# pure-Rust CPU BERT inference -- no CUDA, ROCm, SYCL or Metal anywhere in the
# graph -- so nothing forces an accelerator dependency on anyone.
IUSE="+systemd"

# MIT grants redistribution of both source and binary form, so neither bindist
# nor mirror is warranted; only stripping is restricted, because upstream's
# release profile already stripped the binary and a prebuilt we cannot rebuild
# must not be rewritten by portage.
RESTRICT="strip"

QA_PREBUILT="usr/bin/ai-memory"

# Verified with `file`, `ldd` and `readelf` on the 2.1.0 x86_64 and aarch64
# assets: PIE ELF, dynamically linked, DT_NEEDED = libz.so.1, libgcc_s.so.1,
# libm.so.6, libc.so.6, and the highest versioned glibc symbol referenced is
# GLIBC_2.34.  libc and libm are implicit in every profile, so only zlib
# (libz, via virtual/zlib -- sys-libs/zlib is deprecated and zlib-ng[compat]
# provides the same libz.so.1) and gcc (libgcc_s) are named.  Note this is a glibc-linked binary and
# cannot work against musl; ::gentoo handles that class of package with a musl
# profile mask rather than an RDEPEND on sys-libs/glibc, which would be
# unsolvable on musl profiles.
#
# app-misc/ca-certificates because the binary is built with reqwest's
# `rustls-tls-native-roots`: it reads the PLATFORM trust store rather than a
# bundled webpki root set, so an empty store means every provider call fails
# with UnknownIssuer.
#
# The account is NOT created from upstream's sysusers.d drop-in (which this
# ebuild deliberately does not install); it comes from acct-user/ai-memory and
# acct-group/ai-memory, whose home is the /var/lib/ai-memory the unit declares
# as its StateDirectory.
#
# The block is weak and declared only here, following this overlay's own
# precedent in sys-apps/ai-jail-bin.  Both packages install /usr/bin/ai-memory,
# so they cannot coexist -- but nothing in the tree RDEPENDs on ai-memory, so
# portage can order the swap itself rather than stopping to make the user
# emerge -C by hand.  A strong "!!" buys nothing here and costs that.
# The acct-* pair is in DEPEND as well as RDEPEND, and that is load-bearing
# rather than belt-and-braces: src_install runs `fowners root:ai-memory` on
# /etc/ai-memory/env, and fowners is a chown against the BUILD host's account
# database, which only DEPEND guarantees is populated. With them in RDEPEND
# alone the install phase dies with "chown: invalid group: root:ai-memory" on
# any machine that does not already have the account. Same shape as
# net-misc/apt-cacher-ng and net-misc/asterisk in ::gentoo.
DEPEND="
	acct-group/ai-memory
	acct-user/ai-memory
"
RDEPEND="
	${DEPEND}
	!dev-util/ai-memory
	app-misc/ca-certificates
	sys-devel/gcc:*
	virtual/zlib
"

DOCS=( README.md docs/install.md )

src_install() {
	dobin ${MY_PN}
	einstalldocs

	# Agent hook scripts: shell plus one subdirectory per vendor
	# (claude-code, codex, cursor, ...). Copied with `cp -a` rather than
	# `doins -r` on purpose: the agents EXEC these files, and 80 of the 162
	# ship 0755 in the release tarball while doins forces 0644 on everything
	# it touches. A 0644 hook is a hook that silently never runs, and nothing
	# in the install would have looked wrong. Same call upstream's PKGBUILD
	# makes. Measured on the 2.1.0 x86_64 asset: 80 executable before, 0 after
	# a doins -r.
	dodir /usr/share/${MY_PN}
	cp -a hooks "${ED}"/usr/share/${MY_PN}/ || die

	# --- configuration -----------------------------------------------------
	insinto /etc/${MY_PN}
	newins crates/ai-memory-cli/templates/config.default.toml config.toml

	# The env file is meant to hold API keys (ANTHROPIC_API_KEY, ...), so it
	# is readable by the service account and by nobody else. 0640 root:ai-memory
	# matches what upstream ships (0640) while making the group the one that
	# actually needs to read it.
	newins packaging/env/${MY_PN}.env env
	fowners root:${MY_PN} /etc/${MY_PN}/env
	fperms 0640 /etc/${MY_PN}/env

	# --- state directory ---------------------------------------------------
	# StateDirectory=/StateDirectoryMode= only exist inside systemd. The
	# tmpfiles entry is what creates /var/lib/ai-memory 0750 ai-memory:ai-memory
	# on a non-systemd host too (opentmpfiles/systemd-tmpfiles both read it),
	# and the OpenRC service repeats it in start_pre so the daemon does not
	# depend on tmpfiles having run.
	newtmpfiles packaging/tmpfiles/${MY_PN}.conf ${MY_PN}.conf

	# --- service files -----------------------------------------------------
	# One service per scope, mirroring the two units upstream ships. The
	# OpenRC scripts are installed UNCONDITIONALLY: they cost a systemd user
	# nothing, and gating them would leave someone without systemd no way to
	# run the daemon at all. Only the units are behind USE=systemd.
	newinitd "${FILESDIR}"/${MY_PN}.initd ${MY_PN}
	newconfd "${FILESDIR}"/${MY_PN}.confd ${MY_PN}

	# User scope. newinitd has no user-scope variant, so the script goes in
	# as a plain executable, following sys-apps/xdg-desktop-portal and
	# sci-ml/lemonade-bin.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/${MY_PN}-user.initd ${MY_PN}

	if use systemd; then
		systemd_dounit packaging/systemd/${MY_PN}.service
		# Upstream's file is ai-memory-user.service; the user manager looks
		# for ai-memory.service in the user directory, hence the rename.
		systemd_newuserunit packaging/systemd/${MY_PN}-user.service ${MY_PN}.service
	fi
	# packaging/sysusers/ai-memory.conf is deliberately NOT installed: the
	# account comes from acct-user/ai-memory + acct-group/ai-memory.

	# --- shell completions -------------------------------------------------
	# Generated from the binary that is about to be installed. `ai-memory
	# completions <shell>` renders the same derived clap Command the parser
	# uses, so the scripts cannot drift from the real CLI surface; a checked-in
	# script could. The subcommand takes no config and touches no data
	# directory, so it is safe to run here.
	#
	# SRC_URI fetches the asset matching the TARGET arch, so on a native build
	# the binary always runs. Only a cross (or otherwise emulated) build lands
	# an unrunnable binary here, which is the same condition the from-source
	# ebuild guards on -- hence the same guard, not a different one.
	if ! tc-is-cross-compiler; then
		local shell
		for shell in bash zsh fish; do
			./${MY_PN} completions ${shell} > "${T}"/${MY_PN}.${shell} \
				|| die "generating ${shell} completions failed"
		done
		newbashcomp "${T}"/${MY_PN}.bash ${MY_PN}
		newzshcomp "${T}"/${MY_PN}.zsh _${MY_PN}
		newfishcomp "${T}"/${MY_PN}.fish ${MY_PN}.fish
	else
		ewarn "Cross-compiling: shell completions were not generated."
	fi
}

pkg_postinst() {
	tmpfiles_process ${MY_PN}.conf

	elog "Start the system-wide server with one of:"
	elog "    rc-service ${MY_PN} start"
	elog "    systemctl enable --now ${MY_PN}.service"
	elog
	elog "Or run it in your own session (data under ~/.local/share/${MY_PN}):"
	elog "    rc-service --user ${MY_PN} start"
	elog "    systemctl --user enable --now ${MY_PN}.service"
	elog
	elog "API keys and other secrets belong in /etc/${MY_PN}/env (0640"
	elog "root:${MY_PN}) for the system service, or ~/.config/${MY_PN}/env for the"
	elog "user one. Server settings live in /etc/${MY_PN}/config.toml."
	elog
	elog "Agent hook scripts are installed under /usr/share/${MY_PN}/hooks."
}
