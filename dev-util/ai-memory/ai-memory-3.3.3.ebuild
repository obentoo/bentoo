# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# CRATES is deliberately empty: the 494 crates come from a single tarball in
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
# Verified for 2.1.0, 2.2.2, 2.4.0 and 2.5.0: the member-scoped run covers all
# 494 external crates the workspace resolves -- generated list and the previous
# inline CRATES list were compared entry by entry, with no difference in either
# direction.
#
# 3.1.0 lists four crates inline ON TOP of the reused 3.0.1 tarball: they are
# the only registry entries its lock added (503 -> 507), so a top-up avoids
# re-uploading 39 MiB for four Windows-only crates. Cargo still needs them:
# it resolves the whole lock before it filters by target. Drop them the next
# time the tarball is regenerated -- the recipe above already includes them.
#
# 3.2.0 tops up two more, again an autoupdate bump that moved PV alone: the
# lock moved rustls-webpki 0.103.15 -> 0.103.16 and webpki-root-certs
# 1.0.9 -> 1.0.10, and the build died with "failed to select a version for
# the requirement `rustls-webpki = "^0.103.14"` (locked to 0.103.16)".
# Those two are the whole diff between the lock's registry entries and
# tarball + CRATES (505 entries); the leftovers the lock dropped (zip 8.6.0,
# basic-toml, and the two older versions) are unused and harmless.
#
# 3.2.3 tops up two more, the same way: the lock moved tokio 1.52.3 -> 1.54.1
# and added ruzstd 0.9.1 (new to the set), and the build died with "failed to
# select a version for the requirement `tokio = "^1"` (locked to 1.54.1)".
# Eight top-ups now: the next bump that touches the lock should regenerate
# the tarball instead.
#
# 3.2.10 tops up a ninth anyway, deliberately: the only registry change in
# its lock is libz-sys 1.1.28 -> 1.1.31 (pulled by libgit2-sys), and one
# crate does not justify re-uploading 39 MiB. Regenerate on the next one.
CRATES="
	libz-sys@1.1.31
	ruzstd@0.9.1
	rustls-webpki@0.103.16
	tokio@1.54.1
	webpki-root-certs@1.0.10
	windows-link@0.100.0
	windows-registry@0.100.0
	windows-result@0.100.0
	windows-strings@0.100.0
"

# 3.1.0 replaced crates.io's zip with a [patch.crates-io] git pin on the
# v8.6.0 release commit: crates.io yanked every zip 8.x compatible with
# candle 0.11. 3.2.10 moved the pin to upstream's 8.x security backport for
# GHSA-m665-v7pm-7grj; the guard in src_prepare dies when it moves again.
# The tarball's registry zip-8.6.0 is now unused. Remove this
# entry once upstream drops the patch.
declare -A GIT_CRATES=(
	[zip]='https://github.com/zip-rs/zip2;507c5c76ddd4cde767e64832fc6f848c51a99e44;zip2-%commit%'
)

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
# 2.5.0, a third time: zip 8.6 pulled in zopfli 0.8.3 and zlib-rs 0.6.3
# (492 -> 494), and the build died with "no matching package named `zopfli`
# found ... required by package `zip v8.6.0`".
#
# 2.6.7, a fourth time, and this one was an autoupdate bump that moved PV
# alone: the YAML layer swapped serde_yaml + unsafe-libyaml for serde-saphyr
# (+ granit-parser and friends) and quinn-proto went 0.11.15 -> 0.11.19
# (494 -> 503), and the build died with "no matching package named
# `serde-saphyr` found".
#
# 3.0.1, a fifth time, again an autoupdate bump that moved PV alone: the lock
# moved rustls 0.23.45 -> 0.23.46, and the build died with "failed to select a
# version for the requirement `rustls = "^0.23"` (locked to 0.23.46)" -- the
# same message 2.2.2 hit. 503 crates, set unchanged in size.
#
# BUMP THIS to ${PV} (and run the recipe above) the moment the lock's external
# packages change -- a stale tarball still FETCHES, so the failure would land
# in src_compile as a missing crate rather than here.
CRATES_PV="3.0.1"

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
KEYWORDS="~amd64"
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

	# zip comes from upstream's own [patch.crates-io] as a git dependency,
	# and cargo never applies a patch to a patch: the [patch."<url>"] that
	# cargo.eclass writes for GIT_CRATES is ignored and the offline build
	# dies with "can't checkout from 'https://github.com/zip-rs/zip2'".
	# Point the upstream patch at the unpacked GIT_CRATES tarball instead.
	local zip_git='zip = { git = "https://github.com/zip-rs/zip2", rev = "507c5c76ddd4cde767e64832fc6f848c51a99e44" }'
	grep -qxF "${zip_git}" Cargo.toml \
		|| die "Cargo.toml no longer pins zip to zip2@507c5c76; update GIT_CRATES and this sed"
	sed -i "s|^zip = { git = .*|zip = { path = \"${WORKDIR}/zip2-507c5c76ddd4cde767e64832fc6f848c51a99e44\" }|" \
		Cargo.toml || die

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
	#
	# Single-threaded since 3.1.0: the upgrade_e2e tests in tests/suite
	# write a fixture executable and exec it; another test thread forking
	# meanwhile inherits the still-open write fd, and the exec fails with
	# ETXTBSY ("Text file busy"). 2 of 287 failed in parallel; serially all
	# pass, as do the two alone. Serial costs ~80 s for the whole phase.
	# Splitting off the library to keep it parallel does not pay: --tests
	# includes the lib target, so it would run twice (~88 s).
	#
	# Through RUST_TEST_THREADS, not `-- --test-threads=1`: cargo_src_test
	# already appends its own `--`, so a second one turns the flag into a
	# test-name filter that matches nothing -- the phase then "passes" with
	# 0 tests run and all 287 filtered out.
	local -x RUST_TEST_THREADS=1
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
