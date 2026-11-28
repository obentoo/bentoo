# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	adler2@2.0.1
	aho-corasick@1.1.5
	anstream@1.0.0
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anstyle@1.0.14
	anyhow@1.0.104
	base64@0.23.1
	bitflags@2.13.2
	bitvec@1.1.1
	block-buffer@0.12.1
	borsh@1.8.1
	bstr@1.14.0
	bytes@1.12.2
	camino@1.2.6
	cc@1.11.2
	cfg-expr@0.20.11
	cfg-if@1.0.5
	cfg_aliases@0.2.2
	clap@4.6.8
	clap_builder@4.6.7
	clap_lex@1.1.2
	codespan-reporting@0.13.1
	codespan@0.13.1
	colorchoice@1.0.5
	console@0.16.6
	cpufeatures@0.3.1
	crc32fast@1.5.5
	crossbeam-channel@0.5.17
	crossbeam-deque@0.8.8
	crossbeam-epoch@0.9.21
	crossbeam-queue@0.3.14
	crossbeam-utils@0.8.23
	crossbeam@0.8.5
	crypto-common@0.2.2
	digest@0.11.3
	displaydoc@0.2.7
	either@1.19.0
	encode_unicode@1.0.0
	equivalent@1.0.3
	errno@0.3.15
	fastrand@2.5.0
	fern@0.7.1
	find-msvc-tools@0.1.15
	fixedbitset@0.5.9
	flate2@1.1.11
	foldhash@0.1.5
	form_urlencoded@1.2.3
	fs_extra@1.3.0
	funty@2.0.0
	getrandom@0.2.17
	getrandom@0.4.3
	globset@0.4.21
	goblin@0.10.7
	hashbrown@0.15.5
	hashbrown@0.17.1
	http@1.5.0
	httparse@1.10.1
	hybrid-array@0.4.15
	icu_collections@2.4.0
	icu_locale_core@2.4.0
	icu_normalizer@2.4.0
	icu_normalizer_data@2.4.0
	icu_properties@2.4.0
	icu_properties_data@2.4.0
	icu_provider@2.4.0
	idna@1.1.0
	idna_adapter@1.2.2
	indexmap@2.14.2
	insta@1.49.0
	is_terminal_polyfill@1.70.2
	itoa@1.0.19
	jiff-core@1.0.1
	jiff-static@1.0.1
	jiff@1.0.1
	jobserver@0.1.35
	krates@0.22.0
	libc@0.2.191
	linux-raw-sys@0.12.1
	litemap@0.8.3
	lock_api@0.5.0
	log@0.4.35
	memchr@2.8.3
	memmap2@0.9.12
	miniz_oxide@0.9.1
	nu-ansi-term@0.50.3
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	parking_lot@0.13.0
	parking_lot_core@0.10.0
	percent-encoding@2.3.2
	petgraph@0.8.3
	pkg-config@0.3.34
	plain@0.2.3
	portable-atomic-util@0.2.8
	portable-atomic@1.15.0
	potential_utf@0.1.6
	proc-macro2@1.0.107
	quote@1.0.47
	r-efi@6.0.0
	radium@0.7.0
	rayon-core@1.13.0
	rayon@1.12.0
	redox_syscall@0.9.5
	regex-automata@0.4.19
	regex-syntax@0.8.12
	regex@1.13.2
	ring@0.17.14
	rustc-stable-hash@0.1.2
	rustix@1.1.6
	rustls-pki-types@1.16.0
	rustls-webpki@0.103.17
	rustls@0.23.46
	same-file@1.0.6
	scopeguard@1.2.0
	scroll@0.13.0
	scroll_derive@0.13.2
	semver@1.0.28
	serde@1.0.229
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.154
	sha2@0.11.1
	shlex@2.0.1
	simd-adler32@0.3.10
	similar@2.7.0
	smallvec@1.16.6
	smol_str@0.3.7
	spdx@0.13.6
	stable_deref_trait@1.2.1
	strsim@0.11.1
	subtle@2.6.1
	syn@3.0.10
	synstructure@0.14.0
	tame-index@0.27.2
	tap@1.0.1
	target-lexicon@0.13.5
	tempfile@3.27.0
	termcolor@1.4.1
	tinystr@0.8.5
	tinyvec@1.13.3
	toml-span@0.7.2
	twox-hash@2.1.5
	typenum@1.20.1
	unicode-ident@1.0.27
	unicode-normalization@0.1.26
	unicode-width@0.2.3
	untrusted@0.9.0
	ureq-proto@0.7.1
	ureq@3.5.2
	url@2.5.9
	utf8-zero@0.8.1
	utf8_iter@1.1.0
	utf8parse@0.2.2
	utf_types@1.0.0
	walkdir@2.5.0
	wasi@0.11.1+wasi-snapshot-preview1
	webpki-roots@1.0.12
	winapi-util@0.1.11
	windows-link@0.2.1
	windows-sys@0.52.0
	windows-sys@0.61.2
	windows-targets@0.52.6
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_msvc@0.52.6
	windows_i686_gnu@0.52.6
	windows_i686_gnullvm@0.52.6
	windows_i686_msvc@0.52.6
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_msvc@0.52.6
	writeable@0.6.4
	wyz@0.5.1
	yoke-derive@0.8.4
	yoke@0.8.4
	zerofrom-derive@0.1.8
	zerofrom@0.1.8
	zeroize@1.9.2
	zerotrie@0.2.5
	zerovec-derive@0.11.7
	zerovec@0.11.9
	zlib-rs@0.6.8
	zmij@1.0.23
	zstd-safe@7.4.1
	zstd-sys@2.1.3+zstd.1.5.7
	zstd@0.13.5
"

RUST_MIN_VER="1.89.0"

inherit cargo

DESCRIPTION="Cargo plugin to lint licenses, advisories, bans and sources of dependencies"
HOMEPAGE="https://github.com/EmbarkStudios/cargo-deny"

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/EmbarkStudios/cargo-deny.git"
	inherit git-r3
else
	SRC_URI="
		https://github.com/EmbarkStudios/cargo-deny/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
		${CARGO_CRATE_URIS}
	"
	KEYWORDS="~amd64"
fi

# cargo-deny itself is dual-licensed MIT OR Apache-2.0
LICENSE="|| ( Apache-2.0 MIT )"
# Dependent crate licenses
LICENSE+="
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD-2 BSD
	CDLA-Permissive-2.0 ISC MIT Unicode-3.0 ZLIB
"
SLOT="0"

BDEPEND="virtual/pkgconfig"

# rust does not use *FLAGS from make.conf, silence portage warning
QA_FLAGS_IGNORED="usr/bin/${PN}"

src_compile() {
	cargo_src_compile
}

src_install() {
	dobin "$(cargo_target_dir)/${PN}"
	einstalldocs
}
