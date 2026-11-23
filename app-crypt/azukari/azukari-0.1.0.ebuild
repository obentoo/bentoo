# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	aes@0.9.4
	ashpd@0.14.3
	async-trait@0.1.92
	autocfg@1.5.1
	bitflags@2.13.2
	block-buffer@0.12.1
	block-padding@0.4.2
	bumpalo@3.20.4
	bytes@1.12.2
	cbc@0.2.1
	cfg-if@1.0.5
	cipher@0.5.2
	cmov@0.5.4
	const-oid@0.10.3
	cpubits@0.1.1
	cpufeatures@0.3.1
	crypto-common@0.2.2
	ctutils@0.4.8
	digest@0.11.3
	endi@1.1.1
	errno@0.3.15
	fastrand@2.5.0
	futures-core@0.3.34
	futures-io@0.3.34
	futures-macro@0.3.34
	futures-task@0.3.34
	futures-util@0.3.34
	getrandom@0.3.4
	getrandom@0.4.3
	hex@0.4.3
	hkdf@0.13.0
	hmac@0.13.0
	hybrid-array@0.4.15
	inout@0.2.6
	itoa@1.0.19
	js-sys@0.3.107
	libc@0.2.191
	libm@0.2.16
	linux-raw-sys@0.12.1
	md-5@0.11.0
	memchr@2.8.3
	memoffset@0.9.1
	mio@1.2.5
	num-bigint-dig@0.9.1
	num-bigint@0.4.8
	num-complex@0.4.6
	num-integer@0.1.47
	num-iter@0.1.46
	num-rational@0.4.2
	num-traits@0.2.19
	num@0.4.3
	once_cell@1.21.4
	oo7@0.7.3
	ordered-stream@0.2.0
	pbkdf2@0.13.0
	pin-project-lite@0.2.18
	ppv-lite86@0.2.21
	proc-macro2@1.0.107
	quote@1.0.47
	r-efi@5.3.0
	r-efi@6.0.0
	rand@0.9.5
	rand_chacha@0.9.0
	rand_core@0.9.5
	rustix@1.1.6
	rustversion@1.0.23
	serde@1.0.229
	serde_bytes@0.11.19
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.154
	serde_repr@0.1.21
	sha2@0.11.1
	signal-hook-registry@1.4.8
	slab@0.4.12
	smallvec@1.16.6
	socket2@0.6.5
	subtle@2.6.1
	syn@2.0.119
	syn@3.0.10
	tempfile@3.27.0
	tokio@1.54.1
	tracing-attributes@0.1.31
	tracing-core@0.1.36
	tracing@0.1.44
	typenum@1.20.1
	uds_windows@1.2.1
	unicode-ident@1.0.27
	uuid@1.29.3
	wasi@0.11.1+wasi-snapshot-preview1
	wasip2@1.0.4+wasi-0.2.12
	wasm-bindgen-macro-support@0.2.130
	wasm-bindgen-macro@0.2.130
	wasm-bindgen-shared@0.2.130
	wasm-bindgen@0.2.130
	windows-link@0.2.1
	windows-sys@0.61.2
	winnow@1.0.5
	wit-bindgen@0.57.1
	zbus@6.5.0
	zbus_macros@6.5.0
	zbus_utils@6.1.0
	zcheapstr@1.4.0
	zerocopy-derive@0.8.64
	zerocopy@0.8.64
	zeroize@1.9.2
	zeroize_derive@1.5.0
	zgvariant@2.0.0
	zgvariant_derive@2.0.0
	zmij@1.0.23
	zruntime@0.2.4
"

# Cargo.toml: edition 2024, rust-version 1.95 (the floor oo7 0.7.3 declares).
RUST_MIN_VER="1.95"

inherit cargo

DESCRIPTION="Exec a command with secret:// references resolved from the Secret Service"
HOMEPAGE="https://github.com/zeo-workspace/azukari"
SRC_URI="
	https://github.com/zeo-workspace/azukari/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	${CARGO_CRATE_URIS}
"

LICENSE="|| ( Apache-2.0 MIT )"
# Dependent crate licenses
LICENSE+=" BSD MIT Unicode-3.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="test"
RESTRICT="!test? ( test )"

# azukari is a Secret Service client: without a provider on the session bus
# every reference fails to resolve. The virtual picks one (gnome-keyring,
# kwallet-runtime[keyring], keepassxc, ...). app-crypt/oo7 is deliberately not
# named: its oo7-daemon is not installable from this overlay yet.
RDEPEND="virtual/secret-service"
# tests/fake_service.rs starts a private dbus-daemon for its fake Secret
# Service. tests/oo7_daemon_service.rs also wants oo7-daemon and skips itself,
# loudly, when it is absent, so it is not a test dependency.
BDEPEND="test? ( sys-apps/dbus )"

DOCS=( README.md CHANGELOG.md SECURITY.md )

src_prepare() {
	default

	# [profile.release] sets strip = true. The eclass passes -C strip=none in
	# RUSTFLAGS, but sys-apps/ai-jail and app-misc/zeo-systray still received
	# pre-stripped binaries from the same profile setting, which trips the
	# pre-stripped QA check and leaves FEATURES=splitdebug with empty debug
	# files. Dropping it at the source lets Portage strip, rather than
	# silencing the check with QA_PRESTRIPPED.
	grep -qx 'strip = true' Cargo.toml \
		|| die "Cargo.toml no longer sets strip = true; drop this sed"
	sed -i '/^strip = true$/d' Cargo.toml || die
}

src_test() {
	# Upstream's suite (Makefile `test`) builds with test-support, which adds
	# the azukari-memstore launcher the exec and leak tests drive. The release
	# build in src_compile never enables it, so that binary is not installed.
	cargo_src_test --features test-support
}

src_install() {
	# Only azukari. azukari-memstore is a test fixture (required-features =
	# test-support) and must never reach a system.
	dobin "$(cargo_target_dir)"/${PN}
	einstalldocs
}
