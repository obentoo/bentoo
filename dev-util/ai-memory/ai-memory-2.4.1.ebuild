# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# CRATES is deliberately empty: the 492 crates come from a single tarball in
# SRC_URI instead. Listing them inline works -- it is what this package did
# first, and it built -- but Portage answers it with
#
#   QA Notice: This package uses a very large number of CRATES. Please provide
#   a crate tarball instead and fetch it via SRC_URI.
#
# and it puts ~490 DIST lines (151 KiB) in the Manifest. Same precedent as
# dev-util/codex in this overlay.
#
# REGENERATING IT ON A BUMP -- the tarball is NOT produced by upstream and no
# CI makes it, so a bump that skips this fails at fetch time. From the unpacked
# source, and from the workspace MEMBER, never the workspace root (pycargoebuild
# refuses the root with "The specified directory is a workspace root"):
#
#   cd crates/ai-memory-cli
#   name="${PN}-${CRATES_PV}-crates.tar.xz"
#   pycargoebuild -w --crate-tarball-path "${DISTDIR}/${name}" \
#       -d "${DISTDIR}" -o /tmp/throwaway.ebuild -f -M .
#   npx --yes wrangler@latest r2 object put "obentoo-distfiles/${name}" \
#       --file="${DISTDIR}/${name}" --content-type=application/x-xz --remote
#
# The --remote is load-bearing: without it wrangler writes to local dev storage,
# prints "Upload complete" and the object never reaches the bucket. Run it from
# /home/otaku/Projetos/git/bentoo so the wrangler profile resolves to "bentoo";
# the default profile is a different account entirely.
#
# `-o /dev/null` (what this recipe used to say) is NOT usable: pycargoebuild
# writes the ebuild through a tempfile in the DESTINATION directory, so it dies
# with PermissionError on /dev and leaves behind a plausible-looking tarball
# built from whatever was already cached. A real run takes ~3 min and logs
# "Processed N out of <total>" followed by "Crate tarball written to"; an
# aborted one finishes in seconds without them. `-M` keeps it from calling
# `pkgdev manifest` on the whole overlay by itself.
#
# Verified for 2.1.0, 2.2.2 and 2.4.0: the member-scoped run covers all
# 492 external crates the workspace resolves -- generated list and the previous
# inline CRATES list were compared entry by entry, with no difference in either
# direction.
CRATES="
"

# Version of the crates tarball to fetch, which is NOT always ${PV}: when a
# bump leaves the external crate set untouched, the previous artifact is
# reused instead of re-uploading a byte-identical 36 MiB file (2.1.1 reused
# 2.1.0's this way).
#
# 2.2.2 could NOT reuse it: the lock moved rustls 0.23.40 -> 0.23.45 and
# rustls-webpki 0.103.13 -> 0.103.15, and the stale tarball still fetched,
# so the failure landed in src_compile as "failed to select a version for
# the requirement `rustls` (locked to 0.23.45)". Comparing the lock's
# `source = "registry+..."` entries against cargo_home/gentoo/ in the
# candidate tarball is the check that catches it before that.
#
# 2.4.0 repeated it, one release later: the lock gained rmcp 2.2.0,
# rmcp-macros 2.2.0, sse-stream 0.2.6, utf16_iter 1.0.5 and write16 1.0.0
# (490 -> 492 crates), and the build died with "failed to select a version for
# the requirement `rmcp = "^2.2"` (locked to 2.2.0)". Same shape, same fix.
#
# BUMP THIS to ${PV} (and run the recipe above) the moment the lock's external
# packages change -- a stale tarball still FETCHES, so the failure would land
# in src_compile as a missing crate rather than here.
CRATES_PV="2.4.0"

# Upstream pins channel 1.95 in rust-toolchain.toml; the workspace is
# edition 2024 and declares rust-version = "1.95".
RUST_MIN_VER="1.95"

inherit cargo shell-completion systemd tmpfiles toolchain-funcs

DESCRIPTION="Local-first long-term memory MCP server for AI coding agents"
HOMEPAGE="https://github.com/akitaonrails/ai-memory"
SRC_URI="
	https://github.com/akitaonrails/ai-memory/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://distfiles.obentoo.org/${PN}-${CRATES_PV}-crates.tar.xz
	${CARGO_CRATE_URIS}
"

# License for the package itself
LICENSE="MIT"
# Dependent crate licenses
LICENSE+="
	Apache-2.0 BSD CC0-1.0 CDLA-Permissive-2.0 ISC MIT MPL-2.0
	Unicode-3.0 ZLIB
"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
# No USE flag for the LLM crate's `local-embeddings` feature, and that is a
# measurement rather than an omission.  The feature is default-on in
# crates/ai-memory-llm (`default = ["local-embeddings"]`), which is what the
# official x86_64/aarch64 release binaries ship, and it is pure-Rust CPU BERT
# inference: no CUDA, ROCm, SYCL or Metal feature is enabled anywhere in the
# graph, so nobody is being handed an accelerator dependency by leaving it on.
#
# It cannot be turned off from a `-p ai-memory-cli` build either.
# crates/ai-memory-cli/Cargo.toml takes the dependency as
# `ai-memory-llm.workspace = true` with no feature spec, and cargo has no
# command-line way to clear a *dependency's* default features.  Adding
# `default-features = false` there alone is rejected outright:
#
#     error inheriting `ai-memory-llm` from workspace root manifest's
#     `workspace.dependencies.ai-memory-llm`
#     `default-features = false` cannot override workspace's `default-features`
#
# and even past that the CLI would not compile: config.rs and commands/serve.rs
# name `EmbedderChoice::Local`, `LOCAL_MODEL`, `model_present` and `fetch_model`
# with no `#[cfg(feature = ...)]` around them, and "local" is the default
# embedding provider when none is configured.
#
# CONDITION TO REVISIT: expose the flag once upstream adds a feature
# passthrough in crates/ai-memory-cli (or once those call sites are cfg-gated).
# Until then a flag here would either be a no-op or an FTBFS.
IUSE="+systemd"

# app-misc/ca-certificates because reqwest is built with
# `rustls-tls-native-roots`: it reads the PLATFORM trust store rather than a
# bundled webpki root set, so an empty store means every provider call fails
# with UnknownIssuer.
#
# The account is NOT created from upstream's sysusers.d drop-in (which this
# ebuild deliberately does not install); it comes from acct-user/ai-memory and
# acct-group/ai-memory, whose home is the /var/lib/ai-memory the unit declares
# as its StateDirectory.
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
	app-misc/ca-certificates
"

DOCS=( README.md docs/install.md )

src_prepare() {
	default

	# [profile.release] sets strip = "symbols", which hands Portage an
	# already-stripped binary: that trips the pre-stripped QA check and
	# makes FEATURES=splitdebug produce empty debug objects. Let Portage
	# strip. Guarded because a sed that matches nothing exits 0 in silence,
	# and the fix would then die unnoticed at the next bump.
	grep -qF 'strip = "symbols"' Cargo.toml \
		|| die "Cargo.toml no longer sets strip = \"symbols\"; drop this sed"
	sed -i '/^strip = "symbols"$/d' Cargo.toml || die

	# crates/ai-memory-web/build.rs copies the VENDORED stylesheet into
	# OUT_DIR and only reaches the network when TAILWIND_BUILD=1, which this
	# ebuild never sets. If upstream ever stops vendoring the file, the build
	# script panics with a message about a network regeneration mode -- which
	# reads like a sandbox failure and is not one. Fail here instead, where
	# the cause is stated.
	[[ -f crates/ai-memory-web/static/tailwind.css ]] \
		|| die "crates/ai-memory-web/static/tailwind.css is gone; upstream stopped vendoring the stylesheet and the build now needs TAILWIND_BUILD=1 (network)"
}

src_configure() {
	# The workspace has eleven members plus an evals harness; only
	# ai-memory-cli produces the shipped `ai-memory` binary. `-p` lands in
	# ECARGO_ARGS, so src_compile and src_test both inherit it.
	cargo_src_configure -p ai-memory-cli
}

src_test() {
	# Upstream's own PKGBUILD points HOME at a scratch directory for the
	# suite; several tests write under $HOME and the Portage HOME is
	# read-only in some setups.
	local -x HOME="${T}/test-home"
	mkdir -p "${HOME}" || die

	# --lib --tests, and each half of that is deliberate.
	#
	# Upstream's PKGBUILD runs `--bin ai-memory`, which looks like it tests
	# the shipped binary and does not: crates/ai-memory-cli/Cargo.toml sets
	# `test = false` on that target because main.rs is a shim with no tests
	# of its own. cargo still builds a harness when the target is named
	# explicitly, so the phase passes -- having run zero tests. A test phase
	# that cannot fail is worse than none, because it reads as coverage.
	#
	# --lib --tests runs what actually exists: 846 unit tests in the library
	# plus 110 in tests/suite, all passing here against 2.1.0.
	#
	# Doctests are excluded because one of them is not Rust. The example in
	# commands/setup_agent.rs is a `docker run ...` shell snippet in a plain
	# ``` block, so rustdoc compiles it and dies with "unknown start of
	# token: \". That is an upstream defect in a doc comment, not a fault in
	# this package, and it fails identically on a plain `cargo test` outside
	# Portage. Revisit when upstream tags the block `text` or `ignore`.
	cargo_src_test --lib --tests
}

src_install() {
	dobin target/release/${PN}
	einstalldocs

	# Agent hook scripts: shell plus one subdirectory per vendor
	# (claude-code, codex, cursor, ...). Copied with `cp -a` rather than
	# `doins -r` on purpose: the agents EXEC these files, and 80 of the 162
	# ship 0755 upstream while doins forces 0644 on everything it touches.
	# A 0644 hook is a hook that silently never runs, and nothing in the
	# install would have looked wrong. Same call upstream's PKGBUILD makes.
	dodir /usr/share/${PN}
	cp -a hooks "${ED}"/usr/share/${PN}/ || die

	# --- configuration -----------------------------------------------------
	insinto /etc/${PN}
	newins crates/ai-memory-cli/templates/config.default.toml config.toml

	# The env file is meant to hold API keys (ANTHROPIC_API_KEY, ...), so it
	# is readable by the service account and by nobody else. 0640 root:ai-memory
	# matches what upstream ships (0640) while making the group the one that
	# actually needs to read it.
	newins packaging/env/${PN}.env env
	fowners root:${PN} /etc/${PN}/env
	fperms 0640 /etc/${PN}/env

	# --- state directory ---------------------------------------------------
	# StateDirectory=/StateDirectoryMode= only exist inside systemd. The
	# tmpfiles entry is what creates /var/lib/ai-memory 0750 ai-memory:ai-memory
	# on a non-systemd host too (opentmpfiles/systemd-tmpfiles both read it),
	# and the OpenRC service repeats it in start_pre so the daemon does not
	# depend on tmpfiles having run.
	newtmpfiles packaging/tmpfiles/${PN}.conf ${PN}.conf

	# --- service files -----------------------------------------------------
	# One service per scope, mirroring the two units upstream ships. The
	# OpenRC scripts are installed UNCONDITIONALLY: they cost a systemd user
	# nothing, and gating them would leave someone without systemd no way to
	# run the daemon at all. Only the units are behind USE=systemd.
	newinitd "${FILESDIR}"/${PN}.initd ${PN}
	newconfd "${FILESDIR}"/${PN}.confd ${PN}

	# User scope. newinitd has no user-scope variant, so the script goes in
	# as a plain executable, following sys-apps/xdg-desktop-portal and
	# sci-ml/lemonade-bin.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/${PN}-user.initd ${PN}

	if use systemd; then
		systemd_dounit packaging/systemd/${PN}.service
		# Upstream's file is ai-memory-user.service; the user manager looks
		# for ai-memory.service in the user directory, hence the rename.
		systemd_newuserunit packaging/systemd/${PN}-user.service ${PN}.service
	fi
	# packaging/sysusers/ai-memory.conf is deliberately NOT installed: the
	# account comes from acct-user/ai-memory + acct-group/ai-memory.

	# --- shell completions -------------------------------------------------
	# Generated from the binary just built. `ai-memory completions <shell>`
	# renders the same derived clap Command the parser uses, so the scripts
	# cannot drift from the real CLI surface; a checked-in script could.
	# The subcommand takes no config and touches no data directory, so it is
	# safe to run here -- but it is still running a freshly built target
	# binary, which a cross build cannot do.
	if ! tc-is-cross-compiler; then
		local shell
		for shell in bash zsh fish; do
			target/release/${PN} completions ${shell} > "${T}"/${PN}.${shell} \
				|| die "generating ${shell} completions failed"
		done
		newbashcomp "${T}"/${PN}.bash ${PN}
		newzshcomp "${T}"/${PN}.zsh _${PN}
		newfishcomp "${T}"/${PN}.fish ${PN}.fish
	else
		ewarn "Cross-compiling: shell completions were not generated."
	fi
}

pkg_postinst() {
	tmpfiles_process ${PN}.conf

	elog "Start the system-wide server with one of:"
	elog "    rc-service ${PN} start"
	elog "    systemctl enable --now ${PN}.service"
	elog
	elog "Or run it in your own session (data under ~/.local/share/${PN}):"
	elog "    rc-service --user ${PN} start"
	elog "    systemctl --user enable --now ${PN}.service"
	elog
	elog "API keys and other secrets belong in /etc/${PN}/env (0640"
	elog "root:${PN}) for the system service, or ~/.config/${PN}/env for the"
	elog "user one. Server settings live in /etc/${PN}/config.toml."
	elog
	elog "Agent hook scripts are installed under /usr/share/${PN}/hooks."
}
