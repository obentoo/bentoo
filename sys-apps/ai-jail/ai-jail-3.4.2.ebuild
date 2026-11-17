# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	allocator-api2@0.2.21
	approx@0.5.1
	arrayvec@0.7.6
	autocfg@1.5.1
	bitflags@2.13.2
	block-buffer@0.10.4
	by_address@1.2.1
	castaway@0.2.4
	cc@1.4.7
	cfg_aliases@0.2.1
	cfg-if@1.0.4
	compact_str@0.9.1
	convert_case@0.10.0
	cpufeatures@0.2.17
	crossterm@0.29.0
	crossterm_winapi@0.9.1
	crypto-common@0.1.7
	darling@0.24.1
	darling_core@0.24.1
	darling_macro@0.24.1
	deranged@0.5.9
	derive_more@2.1.1
	derive_more-impl@2.1.1
	digest@0.10.7
	document-features@0.2.12
	either@1.19.0
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	equivalent@1.0.2
	errno@0.3.14
	find-msvc-tools@0.1.13
	foldhash@0.2.0
	generic-array@0.14.7
	getrandom@0.2.17
	hashbrown@0.16.1
	hashbrown@0.17.1
	heck@0.5.0
	ident_case@1.0.1
	indexmap@2.13.0
	indoc@2.0.8
	instability@0.3.14
	itertools@0.14.0
	itoa@1.0.17
	kasuari@0.4.13
	landlock@0.4.4
	lexopt@0.3.2
	libc@0.2.191
	libm@0.2.16
	line-clipping@0.3.8
	linux-raw-sys@0.12.1
	litrs@1.0.1
	lock_api@0.4.14
	log@0.4.35
	lru@0.18.5
	memchr@2.8.0
	mio@1.2.4
	nix@0.29.0
	num-conv@0.2.2
	num_threads@0.1.8
	num-traits@0.2.19
	once_cell@1.21.4
	palette@0.7.7
	palette_derive@0.7.7
	palette_math@0.7.7
	parking_lot@0.12.5
	parking_lot_core@0.9.12
	portable-atomic@1.15.0
	powerfmt@0.2.1
	proc-macro2@1.0.106
	quote@1.0.44
	ratatui@0.30.2
	ratatui-core@0.1.2
	ratatui-crossterm@0.1.2
	ratatui-widgets@0.3.2
	redox_syscall@0.5.18
	ring@0.17.14
	rustc_version@0.4.1
	rustix@1.1.6
	rustls@0.23.46
	rustls-pki-types@1.15.1
	rustls-webpki@0.103.16
	rustversion@1.0.23
	ryu@1.0.23
	scopeguard@1.2.0
	seccompiler@0.5.0
	semver@1.0.28
	serde@1.0.228
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_json@1.0.149
	serde_spanned@0.6.9
	sha2@0.10.9
	shlex@2.0.1
	signal-hook@0.3.18
	signal-hook-mio@0.2.5
	signal-hook-registry@1.4.8
	smallvec@1.16.4
	static_assertions@1.1.0
	strsim@0.11.1
	strum@0.28.0
	strum_macros@0.28.0
	subtle@2.6.1
	syn@2.0.117
	syn@3.0.9
	thiserror@2.0.18
	thiserror-impl@2.0.18
	time@0.3.55
	time-core@0.1.9
	toml@0.8.23
	toml_datetime@0.6.11
	toml_edit@0.22.27
	toml_write@0.1.2
	typenum@1.20.1
	unicode-ident@1.0.24
	unicode-segmentation@1.13.3
	unicode-truncate@2.0.1
	unicode-width@0.2.2
	untrusted@0.9.0
	version_check@0.9.5
	vt100@0.16.2
	vte@0.15.0
	wasi@0.11.1+wasi-snapshot-preview1
	webpki-roots@0.26.11
	webpki-roots@1.0.10
	winapi@0.3.9
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-x86_64-pc-windows-gnu@0.4.0
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_msvc@0.52.6
	windows_i686_gnu@0.52.6
	windows_i686_gnullvm@0.52.6
	windows_i686_msvc@0.52.6
	windows-link@0.2.1
	windows-sys@0.52.0
	windows-sys@0.61.2
	windows-targets@0.52.6
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_msvc@0.52.6
	winnow@0.7.14
	zeroize@1.9.0
	zmij@1.0.21
"

# Upstream pins channel 1.97.1 in rust-toolchain.toml; the crate is edition 2024.
RUST_MIN_VER="1.97.1"

inherit cargo desktop xdg-utils

DESCRIPTION="Sandbox for AI coding agents (bubblewrap on Linux, sandbox-exec on macOS)"
HOMEPAGE="https://github.com/akitaonrails/ai-jail"
SRC_URI="
	https://github.com/akitaonrails/ai-jail/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"

# License for the package itself
LICENSE="GPL-3"
# Dependent crate licenses
LICENSE+=" Apache-2.0 BSD CDLA-Permissive-2.0 ISC MIT Unicode-3.0 ZLIB"
SLOT="0"
KEYWORDS="~amd64"
IUSE="chromium-launcher"

# bwrap is the Linux sandbox backend; ai-jail is a thin wrapper around it and is
# useless without it, so this is a hard runtime dependency, not an optional one.
#
# The block against sys-apps/ai-jail-bin is declared on that package alone --
# see the reasoning there.  One side is enough, and repeating it here would only
# give portage a second edge to reason about.
RDEPEND="
	sys-apps/bubblewrap
	chromium-launcher? ( www-client/chromium )
"

DOCS=( README.md docs )

# Upstream's desktop launcher runs `ai-jail --browser=soft chromium` and nothing
# else, which on Linux leaves the sandbox with an unshared network namespace and
# no display socket -- a browser that cannot open a window or load a page.  The
# patch grants both explicitly and picks --display or --x11 from the session in
# use.  Named without a version so a bump cannot orphan it: the autoupdate
# applier renames ebuilds, never files/.
PATCHES=( "${FILESDIR}"/${PN}-chromium-launcher-caps.patch )

src_prepare() {
	default

	# [profile.release] sets strip = true, which hands Portage an already
	# stripped binary: that trips the pre-stripped QA check and makes
	# FEATURES=splitdebug produce empty debug objects. Let Portage strip.
	grep -qF 'strip = true' Cargo.toml \
		|| die "Cargo.toml no longer sets strip = true; drop this sed"
	sed -i '/^strip = true$/d' Cargo.toml || die
}

src_test() {
	# Unit tests only. tests/sandbox_escape.rs (and the other integration
	# tests) need working unprivileged user namespaces, which the Portage
	# sandbox does not provide; upstream's own PKGBUILD skips them for the
	# same reason.
	cargo_src_test --frozen --bin ai-jail
}

src_install() {
	dobin target/release/${PN}
	einstalldocs

	if use chromium-launcher; then
		dobin dist/desktop/${PN}-chromium
		domenu dist/desktop/${PN}-chromium.desktop
	fi
}

pkg_postinst() {
	use chromium-launcher && xdg_desktop_database_update
}

pkg_postrm() {
	use chromium-launcher && xdg_desktop_database_update
}
