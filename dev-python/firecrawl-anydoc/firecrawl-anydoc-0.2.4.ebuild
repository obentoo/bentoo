# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=maturin
PYPI_VERIFY_REPO=https://github.com/firecrawl/anydoc
PYTHON_COMPAT=( python3_{12..15} )

CRATES="
	adler2@2.0.1
	aes@0.8.4
	aho-corasick@1.1.5
	android_system_properties@0.1.5
	anstream@1.0.0
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anstyle@1.0.14
	autocfg@1.5.1
	bitflags@1.3.2
	bitflags@2.13.1
	block-buffer@0.10.4
	block-buffer@0.12.1
	block-padding@0.3.3
	bumpalo@3.20.3
	cbc@0.1.2
	cc@1.4.0
	cfb@0.14.0
	cfg-if@1.0.4
	chacha20@0.10.1
	chrono@0.4.45
	cipher@0.4.4
	colorchoice@1.0.5
	console@0.16.4
	const-oid@0.10.2
	convert_case@0.11.0
	core-foundation-sys@0.8.7
	cpufeatures@0.2.17
	cpufeatures@0.3.0
	crc32fast@1.5.0
	crossbeam-deque@0.8.7
	crossbeam-epoch@0.9.20
	crossbeam-utils@0.8.22
	crypto-common@0.1.7
	crypto-common@0.2.2
	csv-core@0.1.13
	csv@1.4.0
	ctor@1.0.12
	defmt-macros@1.1.1
	defmt-parser@1.0.0
	defmt@1.1.1
	deranged@0.5.8
	digest@0.10.7
	digest@0.11.3
	ecb@0.1.2
	either@1.17.0
	encode_unicode@1.0.0
	encoding_rs@0.8.35
	env_filter@2.0.0
	env_logger@0.11.11
	equivalent@1.0.2
	errno@0.3.14
	fastrand@2.5.0
	find-msvc-tools@0.1.9
	flate2@1.1.9
	fnv@1.0.7
	futures-channel@0.3.33
	futures-core@0.3.33
	futures-executor@0.3.33
	futures-io@0.3.33
	futures-macro@0.3.33
	futures-sink@0.3.33
	futures-task@0.3.33
	futures-util@0.3.33
	futures@0.3.33
	generic-array@0.14.7
	getrandom@0.4.3
	hashbrown@0.17.1
	heck@0.5.0
	hybrid-array@0.4.14
	iana-time-zone-haiku@0.1.2
	iana-time-zone@0.1.65
	include_dir@0.7.4
	include_dir_macros@0.7.4
	indexmap@2.14.0
	inout@0.1.4
	insta@1.48.0
	is_terminal_polyfill@1.70.2
	itoa@1.0.18
	jiff-core@0.1.0
	jiff-static@0.2.35
	jiff-tzdb-platform@0.1.3
	jiff-tzdb@0.1.8
	jiff@0.2.35
	js-sys@0.3.103
	libc@0.2.189
	libloading@0.9.0
	linux-raw-sys@0.12.1
	log@0.4.33
	lopdf@0.42.0
	md-5@0.10.6
	memchr@2.8.3
	miniz_oxide@0.8.9
	napi-build@2.4.0
	napi-derive-backend@6.1.1
	napi-derive@3.6.2
	napi-sys@3.3.0
	napi@3.12.0
	nohash-hasher@0.2.0
	nom@8.0.0
	num-conv@0.2.2
	num-traits@0.2.19
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	pdf-inspector@1.14.2
	pin-project-lite@0.2.17
	portable-atomic-util@0.2.7
	portable-atomic@1.14.0
	powerfmt@0.2.0
	proc-macro2@1.0.107
	pyo3-build-config@0.29.1
	pyo3-ffi@0.29.1
	pyo3-macros-backend@0.29.1
	pyo3-macros@0.29.1
	pyo3@0.29.1
	quick-xml@0.41.0
	quote@1.0.47
	r-efi@6.0.0
	rand@0.10.2
	rand_core@0.10.1
	rangemap@1.7.1
	rayon-core@1.13.0
	rayon@1.12.0
	regex-automata@0.4.16
	regex-syntax@0.8.11
	regex@1.13.1
	rustc-hash@2.1.3
	rustix@1.1.4
	rustversion@1.0.23
	ryu@1.0.23
	semver@1.0.28
	serde-wasm-bindgen@0.6.5
	serde@1.0.229
	serde_bytes@0.11.19
	serde_core@1.0.229
	serde_derive@1.0.229
	sha2@0.10.9
	sha2@0.11.0
	shlex@2.0.1
	simd-adler32@0.3.10
	similar@2.7.0
	slab@0.4.12
	stringprep@0.1.5
	syn@2.0.119
	syn@3.0.3
	target-lexicon@0.13.5
	tempfile@3.27.0
	thiserror-impl@2.0.19
	thiserror@2.0.19
	time-core@0.1.9
	time-macros@0.2.32
	time@0.3.55
	tinyvec@1.12.0
	tinyvec_macros@0.1.1
	ttf-parser@0.25.1
	typed-path@0.12.3
	typenum@1.20.1
	unicode-bidi@0.3.18
	unicode-ident@1.0.24
	unicode-normalization@0.1.25
	unicode-properties@0.1.4
	unicode-segmentation@1.13.3
	utf8parse@0.2.2
	uuid@1.24.0
	version_check@0.9.5
	wasm-bindgen-macro-support@0.2.126
	wasm-bindgen-macro@0.2.126
	wasm-bindgen-shared@0.2.126
	wasm-bindgen@0.2.126
	web-time@1.1.0
	weezl@0.1.12
	windows-core@0.62.2
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.2.1
	windows-result@0.4.1
	windows-strings@0.5.1
	windows-sys@0.61.2
	zip@8.6.0
	zlib-rs@0.6.6
	zopfli@0.8.3
"
# edition 2024; [package] rust-version in the sdist's Cargo.toml
RUST_MIN_VER="1.88.0"

# The pypi eclass derives SRC_URI from ${PN}/${PV}; cargo.eclass only
# *computes* CARGO_CRATE_URIS, so the crate tarballs are appended below.
inherit cargo distutils-r1 pypi

DESCRIPTION="Convert office documents, PDF and EPUB to GitHub-Flavored Markdown"
HOMEPAGE="
	https://github.com/firecrawl/anydoc/
	https://pypi.org/project/firecrawl-anydoc/
"
SRC_URI+="
	${CARGO_CRATE_URIS}
"

LICENSE="MIT"
# Dependent crate licenses
LICENSE+="
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD ISC MIT Unicode-3.0
	ZLIB
"
SLOT="0"
KEYWORDS="~amd64"

QA_FLAGS_IGNORED="usr/lib.*/py.*/site-packages/anydoc/_anydoc.*\\.so"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

src_unpack() {
	pypi_src_unpack
	cargo_src_unpack
}

python_test() {
	epytest python/tests
}
