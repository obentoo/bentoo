# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	addr2line@0.21.0
	adler2@2.0.1
	adler@1.0.2
	aead@0.5.2
	aho-corasick@1.1.3
	android_log-sys@0.2.0
	android_system_properties@0.1.5
	anstream@0.6.11
	anstyle-parse@0.2.3
	anstyle-query@1.0.2
	anstyle-wincon@3.0.2
	anstyle@1.0.13
	anyhow@1.0.98
	argon2@0.5.3
	arrayref@0.3.9
	arrayvec@0.7.8
	asn1-rs-derive@0.6.0
	asn1-rs-impl@0.2.0
	asn1-rs@0.7.1
	async-broadcast@0.7.2
	async-channel@2.5.0
	async-executor@1.13.3
	async-io@2.6.0
	async-lock@3.4.1
	async-process@2.5.0
	async-recursion@1.1.1
	async-signal@0.2.13
	async-task@4.7.1
	async-trait@0.1.89
	atomic-waker@1.1.2
	autocfg@1.1.0
	aws-lc-fips-sys@0.13.7
	aws-lc-rs@1.15.4
	aws-lc-sys@0.37.1
	backtrace@0.3.69
	base64@0.13.1
	base64@0.21.7
	base64@0.22.1
	base64ct@1.8.3
	bindgen@0.69.5
	bindgen@0.72.1
	bitfield-macros@0.19.4
	bitfield@0.19.4
	bitflags@1.3.2
	bitflags@2.11.0
	blake2@0.10.6
	block-buffer@0.10.4
	blocking@1.6.2
	bumpalo@3.19.0
	bytemuck@1.25.2
	byteorder@1.5.0
	bytes@1.10.1
	c2rust-bitfields-derive@0.18.0
	c2rust-bitfields-derive@0.21.0
	c2rust-bitfields@0.18.0
	c2rust-bitfields@0.21.0
	cairo-rs@0.20.12
	cairo-sys-rs@0.20.10
	camino@1.2.2
	cbindgen@0.28.0
	cc@1.2.56
	cesu8@1.1.0
	cexpr@0.6.0
	cfg-expr@0.18.0
	cfg-if@1.0.0
	cfg_aliases@0.1.1
	cfg_aliases@0.2.1
	chacha20@0.9.1
	chacha20poly1305@0.10.1
	chrono@0.4.44
	cipher@0.4.4
	clang-sys@1.7.0
	clap@4.5.53
	clap_builder@4.5.53
	clap_derive@4.5.49
	clap_lex@0.7.6
	cmake@0.1.54
	colorchoice@1.0.0
	combine@4.6.7
	concurrent-queue@2.5.0
	const_format@0.2.35
	const_format_proc_macros@0.2.34
	convert_case@0.7.1
	core-foundation-sys@0.8.7
	core-foundation@0.10.1
	core-foundation@0.9.4
	cpufeatures@0.2.12
	crc32fast@1.5.0
	crossbeam-channel@0.5.15
	crossbeam-utils@0.8.21
	crypto-common@0.1.6
	curve25519-dalek-derive@0.1.1
	curve25519-dalek@4.1.3
	darling@0.20.10
	darling_core@0.20.10
	darling_macro@0.20.10
	dashmap@5.5.3
	data-encoding@2.9.0
	data-url@0.3.2
	der-parser@10.0.0
	deranged@0.3.11
	derive_more-impl@2.0.1
	derive_more@2.0.1
	digest@0.10.7
	displaydoc@0.2.5
	diva@0.1.0
	dunce@1.0.5
	either@1.9.0
	encoding_rs@0.8.35
	endi@1.1.1
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	equivalent@1.0.1
	errno@0.3.14
	etherparse@0.17.0
	euclid@0.22.14
	event-listener-strategy@0.5.4
	event-listener@5.4.1
	fastbloom@0.9.0
	fastrand@2.0.1
	fdeflate@0.3.7
	fiat-crypto@0.2.9
	field-offset@0.3.6
	find-msvc-tools@0.1.9
	flate2@1.1.2
	float-cmp@0.9.0
	flume@0.11.1
	fnv@1.0.7
	form_urlencoded@1.2.2
	fs_extra@1.3.0
	futures-channel@0.3.31
	futures-core@0.3.31
	futures-executor@0.3.31
	futures-io@0.3.31
	futures-lite@2.6.1
	futures-macro@0.3.31
	futures-sink@0.3.31
	futures-task@0.3.31
	futures-util@0.3.31
	futures@0.3.31
	gdk-pixbuf-sys@0.20.10
	gdk-pixbuf@0.20.10
	gdk4-sys@0.9.6
	gdk4@0.9.6
	generic-array@0.14.7
	getifaddrs@0.2.0
	getrandom@0.2.12
	getrandom@0.3.3
	getrandom@0.4.3
	gimli@0.28.1
	gio-sys@0.20.10
	gio@0.20.12
	glib-macros@0.20.12
	glib-sys@0.20.10
	glib@0.20.12
	glob@0.3.1
	gobject-sys@0.20.10
	graphene-rs@0.20.10
	graphene-sys@0.20.10
	gsk4-sys@0.9.6
	gsk4@0.9.6
	gtk4-macros@0.9.5
	gtk4-sys@0.9.6
	gtk4@0.9.7
	hashbrown@0.12.3
	hashbrown@0.14.3
	hashbrown@0.17.0
	heck@0.4.1
	heck@0.5.0
	hermit-abi@0.3.9
	hermit-abi@0.5.2
	hex@0.4.3
	hmac@0.12.1
	home@0.5.9
	hostname-validator@1.1.1
	http-body-util@0.1.3
	http-body@1.0.0
	http@1.3.1
	httparse@1.10.1
	hyper-rustls@0.27.7
	hyper@1.11.0
	iana-time-zone-haiku@0.1.2
	iana-time-zone@0.1.60
	icu_collections@2.0.0
	icu_locale_core@2.0.0
	icu_normalizer@2.0.0
	icu_normalizer_data@2.0.0
	icu_properties@2.0.1
	icu_properties_data@2.0.1
	icu_provider@2.0.0
	ident_case@1.0.1
	idna@1.1.0
	idna_adapter@1.2.1
	imagesize@0.14.0
	indexmap@1.9.3
	indexmap@2.14.0
	inout@0.1.3
	ip_network@0.4.1
	ip_network_table-deps-treebitmap@0.5.0
	ip_network_table@0.2.0
	ipnet@2.11.0
	ipnetwork@0.21.1
	iri-string@0.7.8
	is-docker@0.2.0
	is-wsl@0.4.0
	itertools@0.12.1
	itertools@0.14.0
	itoa@1.0.10
	javascriptcore6-sys@0.4.0
	javascriptcore6@0.4.0
	jni-sys@0.3.0
	jni@0.21.1
	jobserver@0.1.33
	js-sys@0.3.91
	ksni@0.3.6
	kurbo@0.13.1
	lazy_static@1.4.0
	lazycell@1.3.0
	libadwaita-sys@0.7.2
	libadwaita@0.7.2
	libc@0.2.180
	libloading@0.8.1
	libz-rs-sys@0.5.5
	linux-raw-sys@0.11.0
	linux-raw-sys@0.4.13
	litemap@0.8.0
	lock_api@0.4.11
	log@0.4.29
	logroller@0.1.10
	lru-slab@0.1.2
	lzma-sys@0.1.20
	mac_address@1.1.8
	matchers@0.1.0
	mbox@0.7.1
	memchr@2.8.0
	memoffset@0.9.1
	minimal-lexical@0.2.1
	miniz_oxide@0.7.1
	miniz_oxide@0.8.9
	mio@1.0.2
	nanorand@0.7.0
	netconfig-rs@0.1.5
	netlink-packet-core@0.7.0
	netlink-packet-core@0.8.1
	netlink-packet-route@0.24.0
	netlink-packet-route@0.25.1
	netlink-packet-utils@0.5.2
	netlink-proto@0.12.0
	netlink-sys@0.8.7
	nix@0.26.4
	nix@0.28.0
	nix@0.29.0
	nix@0.30.1
	nix@0.31.1
	nom@7.1.3
	nu-ansi-term@0.46.0
	num-bigint@0.4.6
	num-conv@0.1.0
	num-derive@0.4.2
	num-integer@0.1.46
	num-traits@0.2.18
	object@0.32.2
	oid-registry@0.8.1
	oid@0.2.1
	once_cell@1.21.3
	opaque-debug@0.3.0
	open@5.4.4
	openssl-probe@0.1.6
	ordered-stream@0.2.0
	oslog@0.2.0
	overload@0.1.1
	pango-sys@0.20.10
	pango@0.20.12
	parking@2.2.1
	parking_lot@0.12.1
	parking_lot_core@0.9.9
	password-hash@0.5.0
	paste@1.0.15
	pastey@0.2.2
	percent-encoding@2.3.2
	picky-asn1-der@0.5.6
	picky-asn1-x509@0.15.4
	picky-asn1@0.10.1
	pico-args@0.5.0
	pin-project-lite@0.2.13
	pin-utils@0.1.0
	piper@0.2.4
	pkg-config@0.3.32
	png@0.18.1
	polling@3.11.0
	poly1305@0.8.0
	polycool@0.4.0
	potential_utf@0.1.2
	powerfmt@0.2.0
	ppv-lite86@0.2.17
	prettyplease@0.2.25
	proc-macro-crate@3.4.0
	proc-macro2@1.0.106
	quinn-proto@0.11.12
	quinn-udp@0.5.7
	quinn@0.11.8
	quote@1.0.42
	r-efi@5.2.0
	r-efi@6.0.0
	rand@0.8.5
	rand@0.9.1
	rand_chacha@0.3.1
	rand_chacha@0.9.0
	rand_core@0.6.4
	rand_core@0.9.3
	redox_syscall@0.4.1
	regex-automata@0.1.10
	regex-automata@0.4.6
	regex-syntax@0.6.29
	regex-syntax@0.8.3
	regex@1.10.4
	resvg@0.47.0
	rgb@0.8.53
	ring@0.17.14
	route_manager@0.2.9
	roxmltree@0.21.1
	rtnetlink@0.18.1
	rustc-demangle@0.1.23
	rustc-hash@1.1.0
	rustc-hash@2.1.1
	rustc_version@0.4.0
	rusticata-macros@4.1.0
	rustix@0.38.34
	rustix@1.1.2
	rustls-native-certs@0.8.1
	rustls-pki-types@1.12.0
	rustls-platform-verifier-android@0.1.1
	rustls-platform-verifier@0.5.3
	rustls-platform-verifier@0.6.2
	rustls-webpki@0.103.3
	rustls@0.23.28
	rustversion@1.0.15
	ryu@1.0.16
	safe_arch@0.7.4
	same-file@1.0.6
	schannel@0.1.23
	scopeguard@1.2.0
	sd-notify@0.5.0
	security-framework-sys@2.17.0
	security-framework@3.7.0
	semver@1.0.27
	sendfd@0.4.4
	serde@1.0.228
	serde_bytes@0.11.19
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_json@1.0.140
	serde_repr@0.1.20
	serde_spanned@0.6.8
	serde_spanned@1.1.1
	serde_with@3.12.0
	serde_with_macros@3.12.0
	sharded-slab@0.1.7
	shlex@1.3.0
	signal-hook-registry@1.4.1
	simd-adler32@0.3.8
	simplecss@0.2.2
	siphasher@1.0.1
	slab@0.4.9
	smallvec@1.15.2
	socket2@0.5.10
	socket2@0.6.0
	soup3-sys@0.7.0
	soup3@0.7.0
	spin@0.9.8
	stable_deref_trait@1.2.0
	standard_paths@2.1.0
	static_assertions@1.1.0
	strict-num@0.1.1
	strsim@0.11.1
	strum@0.26.2
	strum@0.27.1
	strum_macros@0.26.2
	strum_macros@0.27.1
	subtle@2.5.0
	svgtypes@0.16.1
	syn@1.0.109
	syn@2.0.118
	sync_wrapper@1.0.2
	synstructure@0.13.2
	system-configuration-sys@0.5.0
	system-deps@7.0.8
	target-lexicon@0.12.16
	target-lexicon@0.13.2
	task-local@0.1.1
	tempfile@3.10.1
	thiserror-impl@1.0.56
	thiserror-impl@2.0.12
	thiserror@1.0.56
	thiserror@2.0.12
	thread_local@1.1.8
	time-core@0.1.2
	time-macros@0.2.19
	time@0.3.37
	tiny-skia-path@0.12.0
	tiny-skia@0.12.0
	tinystr@0.8.1
	tinyvec@1.6.0
	tinyvec_macros@0.1.1
	tokio-macros@2.5.0
	tokio-rustls@0.26.2
	tokio-stream@0.1.17
	tokio-util@0.7.13
	tokio@1.45.1
	toml@0.8.20
	toml@1.1.2+spec-1.1.0
	toml_datetime@0.6.8
	toml_datetime@0.7.0
	toml_datetime@1.1.1+spec-1.1.0
	toml_edit@0.22.24
	toml_edit@0.23.4
	toml_parser@1.1.2+spec-1.1.0
	toml_writer@1.1.1+spec-1.1.0
	tower-http@0.6.8
	tower-layer@0.3.3
	tower-service@0.3.3
	tower@0.5.2
	tracing-android@0.2.0
	tracing-appender@0.2.3
	tracing-attributes@0.1.28
	tracing-core@0.1.33
	tracing-journald@0.3.2
	tracing-log@0.2.0
	tracing-oslog@0.3.0
	tracing-serde@0.1.3
	tracing-subscriber@0.3.18
	tracing@0.1.41
	try-lock@0.2.5
	tss-esapi-sys@0.6.0
	tss-esapi@7.7.0
	tun-rs@2.7.5
	typed-path@0.12.0
	typenum@1.17.0
	uds_windows@1.1.0
	unicode-ident@1.0.12
	unicode-segmentation@1.12.0
	unicode-xid@0.2.6
	universal-hash@0.5.1
	untrusted@0.7.1
	untrusted@0.9.0
	url@2.5.8
	usvg@0.47.0
	utf8_iter@1.0.4
	utf8parse@0.2.1
	uuid@1.17.0
	valuable@0.1.0
	version-compare@0.2.1
	version_check@0.9.4
	walkdir@2.5.0
	want@0.3.1
	wasi@0.11.0+wasi-snapshot-preview1
	wasi@0.14.2+wasi-0.2.4
	wasm-bindgen-futures@0.4.64
	wasm-bindgen-macro-support@0.2.114
	wasm-bindgen-macro@0.2.114
	wasm-bindgen-shared@0.2.114
	wasm-bindgen@0.2.114
	wasm-streams@0.5.0
	web-sys@0.3.91
	web-time@1.1.0
	webkit6-sys@0.4.0
	webkit6@0.4.0
	webpki-root-certs@0.26.11
	webpki-root-certs@1.0.1
	webpki-roots@1.0.0
	which@4.4.2
	wide@0.7.33
	widestring@1.2.1
	winapi-i686-pc-windows-gnu@0.4.0
	winapi-util@0.1.8
	winapi-x86_64-pc-windows-gnu@0.4.0
	winapi@0.3.9
	windows-collections@0.2.0
	windows-collections@0.3.2
	windows-core@0.51.1
	windows-core@0.61.2
	windows-core@0.62.2
	windows-future@0.2.1
	windows-future@0.3.2
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.1.3
	windows-link@0.2.1
	windows-numerics@0.2.0
	windows-numerics@0.3.1
	windows-result@0.3.4
	windows-result@0.4.1
	windows-service@0.8.1
	windows-strings@0.4.2
	windows-strings@0.5.1
	windows-sys@0.45.0
	windows-sys@0.48.0
	windows-sys@0.52.0
	windows-sys@0.59.0
	windows-sys@0.60.2
	windows-sys@0.61.2
	windows-targets@0.42.2
	windows-targets@0.48.5
	windows-targets@0.52.6
	windows-targets@0.53.5
	windows-threading@0.1.0
	windows-threading@0.2.1
	windows@0.61.3
	windows@0.62.2
	windows_aarch64_gnullvm@0.42.2
	windows_aarch64_gnullvm@0.48.5
	windows_aarch64_gnullvm@0.52.6
	windows_aarch64_gnullvm@0.53.1
	windows_aarch64_msvc@0.42.2
	windows_aarch64_msvc@0.48.5
	windows_aarch64_msvc@0.52.6
	windows_aarch64_msvc@0.53.1
	windows_i686_gnu@0.42.2
	windows_i686_gnu@0.48.5
	windows_i686_gnu@0.52.6
	windows_i686_gnu@0.53.1
	windows_i686_gnullvm@0.52.6
	windows_i686_gnullvm@0.53.1
	windows_i686_msvc@0.42.2
	windows_i686_msvc@0.48.5
	windows_i686_msvc@0.52.6
	windows_i686_msvc@0.53.1
	windows_x86_64_gnu@0.42.2
	windows_x86_64_gnu@0.48.5
	windows_x86_64_gnu@0.52.6
	windows_x86_64_gnu@0.53.1
	windows_x86_64_gnullvm@0.42.2
	windows_x86_64_gnullvm@0.48.5
	windows_x86_64_gnullvm@0.52.6
	windows_x86_64_gnullvm@0.53.1
	windows_x86_64_msvc@0.42.2
	windows_x86_64_msvc@0.48.5
	windows_x86_64_msvc@0.52.6
	windows_x86_64_msvc@0.53.1
	winnow@0.7.14
	winnow@1.0.2
	winreg@0.55.0
	wintun@0.5.1
	wit-bindgen-rt@0.39.0
	writeable@0.6.1
	x25519-dalek@2.0.1
	x509-parser@0.17.0
	xmlwriter@0.1.0
	xz2@0.1.7
	yoke-derive@0.8.0
	yoke@0.8.0
	zbus@5.12.0
	zbus_macros@5.12.0
	zbus_names@4.2.0
	zbus_systemd@0.25900.0
	zerofrom-derive@0.1.6
	zerofrom@0.1.6
	zeroize@1.8.1
	zeroize_derive@1.4.2
	zerotrie@0.2.2
	zerovec-derive@0.11.1
	zerovec@0.11.2
	zip@7.2.0
	zlib-rs@0.5.5
	zopfli@0.8.3
	zvariant@5.8.0
	zvariant_derive@5.8.0
	zvariant_utils@3.2.1
"

declare -A GIT_CRATES=(
	[dispatch]='https://github.com/NordSecurity/rust-dispatch;13447cd7221a74ebcce1277ae0cfc9a421a28ec5;rust-dispatch-%commit%'
	[hyper-util]='https://github.com/Sovereign-Engineering/hyper-util;f2659bd55b85bf524abac9ab0ce4951bb67077b9;hyper-util-%commit%'
	[neptun]='https://github.com/Sovereign-Engineering/boringtun;ff3b5555b5b1c4f85ae23d8d4aaf00bea2cd2bf0;boringtun-%commit%/neptun'
	[obscuravpn-api]='https://github.com/Sovereign-Engineering/obscuravpn-api;87d0d9c5a3bf49966eaa8c4840176c3a0c01a52e;obscuravpn-api-%commit%'
	[quinn-proto]='https://github.com/Sovereign-Engineering/quinn;8f690a22535dcf2d76c369cadd3f0bec93667a4d;quinn-%commit%/quinn-proto'
	[quinn-udp]='https://github.com/Sovereign-Engineering/quinn;8f690a22535dcf2d76c369cadd3f0bec93667a4d;quinn-%commit%/quinn-udp'
	[quinn]='https://github.com/Sovereign-Engineering/quinn;8f690a22535dcf2d76c369cadd3f0bec93667a4d;quinn-%commit%/quinn'
	[reqwest]='https://github.com/Sovereign-Engineering/reqwest;7ba2e76a02454b0fa414e0ddbf8aa609ed05b944;reqwest-%commit%'
)

PYTHON_COMPAT=( python3_{12..15} )
# rust-toolchain.toml pins 1.89.0, the only toolchain upstream builds with;
# the newest rust-version any locked crate declares is 1.87 (resvg/usvg).
RUST_MIN_VER="1.89.0"

inherit cargo desktop linux-info python-any-r1 rust-toolchain systemd xdg

# Snapshot of main, not the 1.180 release commit: 1.180 (80afacb4, "Tag
# v1.180.", no git tag -- upstream's v/1.x tags are Android-only) is still
# PolyForm Noncommercial 1.0.0.  The GPL-3 relicense landed four days later
# in 3e55fb3f, and this is the first main HEAD carrying it.  tag.json still
# says 1.180, hence 1.180_p<date>: it sorts before the next tagged release.
EGIT_COMMIT="2bc0738c21ae310b73e442f982d9d82671d9dd4d"

# The GUI renders a React/Vite web UI inside WebKitGTK.  Vite runs at build
# time and upstream gets its dependency tree from `npm ci`, which needs the
# network, so it ships as a separate distfile generated from this snapshot's
# obscura-ui/package-lock.json.  --ignore-scripts plus one pass per
# (cpu, libc) so esbuild's and rollup's native helpers exist for every target
# this ebuild keywords:
#   for t in x64:glibc x64:musl arm64:glibc arm64:musl; do
#     npm ci --ignore-scripts --no-audit --no-fund \
#       --os=linux --cpu=${t%:*} --libc=${t#*:}
#   done   # merge @esbuild/linux-* and @rollup/rollup-linux-* into one tree
#   tar caf obscura-ui-node_modules-${UI_NODE_MODULES_PV}.tar.xz node_modules
# Regenerate it only when package-lock.json changes; otherwise keep the pin.
UI_NODE_MODULES_PV="1.180_p20260924"
UI_NODE_MODULES="obscura-ui-node_modules-${UI_NODE_MODULES_PV}.tar.xz"

DESCRIPTION="Obscura VPN client: CLI, system service and optional GTK desktop app"
HOMEPAGE="
	https://obscura.com/
	https://github.com/Sovereign-Engineering/obscuravpn-client
"
SRC_URI="
	https://github.com/Sovereign-Engineering/obscuravpn-client/archive/${EGIT_COMMIT}.tar.gz
		-> ${P}.tar.gz
	${CARGO_CRATE_URIS}
	gui? ( https://distfiles.obentoo.org/${UI_NODE_MODULES} )
"
S="${WORKDIR}/obscuravpn-client-${EGIT_COMMIT}"

# SPDX "GPL-3.0-only WITH GPL-3.0-linking-source-exception" (obscura and its
# obscuravpn-api crate).  The section 7 grant lets the program be conveyed
# linked with OpenSSL-licensed code (OpenSSL, BoringSSL, AWS-LC, ring), which
# is what GPL-3-with-openssl-exception expresses; ::gentoo has no closer text.
LICENSE="GPL-3-with-openssl-exception"
# Dependent crate licenses
LICENSE+="
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD-2 BSD
	CDLA-Permissive-2.0 ISC MIT MPL-2.0 openssl Unicode-3.0
	Unicode-DFS-2016 Unlicense ZLIB
"
# The web UI bundle: React, Mantine & co. (MIT), localforage (Apache-2.0),
# react-transition-group (BSD), tslib (0BSD), Open Sans (OFL-1.1), and the
# Font Awesome (CC-BY-4.0) and Simple Icons (CC0-1.0) sets from react-icons.
LICENSE+=" gui? ( 0BSD Apache-2.0 BSD CC-BY-4.0 CC0-1.0 MIT OFL-1.1 )"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="gui systemd"

# tss-esapi links tpm2-tss (esys, tctildr, mu); logroller's xz feature links
# the system liblzma through lzma-sys.
COMMON_DEPEND="
	app-arch/xz-utils
	app-crypt/tpm2-tss:=
	gui? (
		dev-libs/glib:2
		gui-libs/gtk:4
		gui-libs/libadwaita:1
		net-libs/libsoup:3.0
		net-libs/webkit-gtk:6
	)
"
DEPEND="${COMMON_DEPEND}"
# sys-apps/shadow: "obscura add-operator" runs usermod to put a user in the
# obscura group.  polkit: the GUI's repair actions go through pkexec.
RDEPEND="
	${COMMON_DEPEND}
	!net-vpn/obscura-bin
	acct-group/obscura
	sys-apps/dbus
	sys-apps/shadow
	gui? ( sys-auth/polkit )
"
BDEPEND="
	virtual/pkgconfig
	gui? (
		${PYTHON_DEPS}
		dev-libs/glib:2
		net-libs/nodejs
	)
"

QA_FLAGS_IGNORED="usr/bin/obscura.*"

# The service owns an "inet obscura" nftables table (conntrack marks,
# owner flag), a tun device, and fwmark policy-routing rules for both
# address families.
CONFIG_CHECK="
	~TUN
	~NF_TABLES
	~NF_TABLES_INET
	~NFT_CT
	~NF_CONNTRACK_MARK
	~IP_MULTIPLE_TABLES
	~IPV6_MULTIPLE_TABLES
"

pkg_setup() {
	linux-info_pkg_setup
	rust_pkg_setup
	use gui && python-any-r1_pkg_setup
}

src_unpack() {
	# cargo_src_unpack unpacks every non-crate archive into ${WORKDIR},
	# so the node_modules tree lands in ${WORKDIR}/node_modules.
	cargo_src_unpack
}

src_prepare() {
	default

	# hyper-util reaches the graph through upstream's own [patch.crates-io]
	# pointing at a git fork.  cargo.eclass redirects git sources with
	# [patch.'<url>'] entries, but cargo cannot patch a patch, so the offline
	# build still tries to clone it.  Point the upstream patch at the
	# unpacked archive instead, taking the commit from GIT_CRATES so the two
	# cannot drift apart (a path carries no revision: a stale one would
	# compile the wrong source silently).  Assert the match first, since sed
	# exits 0 when the pattern is gone.
	local url commit dir
	IFS=';' read -r url commit dir <<< "${GIT_CRATES[hyper-util]}"
	dir=${dir//%commit%/${commit}}
	local line="hyper-util = { git = \"${url}\", rev = \"${commit}\" }"
	grep -qxF "${line}" rustlib/Cargo.toml ||
		die "rustlib/Cargo.toml no longer patches hyper-util as expected"
	sed -i -e "s|^hyper-util = { git = .*|hyper-util = { path = \"${WORKDIR}/${dir}\" }|" \
		rustlib/Cargo.toml || die

	if use gui; then
		ln -s "${WORKDIR}"/node_modules obscura-ui/node_modules || die
	fi
}

src_compile() {
	# Printed in the GUI and CLI, and compared verbatim between the GUI and
	# the service over IPC.  "v" prefix as in upstream's own builds.
	local -x OBSCURA_VERSION="v${PV%_p*}"

	pushd rustlib >/dev/null || die
	# Two builds on purpose, as upstream's flake does: the "gui" feature
	# changes the library both binaries link, and the root daemon should not
	# carry GTK/WebKit.
	cargo_src_compile --bin obscura
	popd >/dev/null || die

	use gui && obscura_compile_gui
}

obscura_compile_gui() {
	local -x OBSCURA_GRESOURCES_DIR="${T}/gresources"
	mkdir -p "${OBSCURA_GRESOURCES_DIR}" || die

	# licenses.json for the GUI's "Licenses" page.  Upstream generates it
	# with cargo-about (Rust) and license-checker (npm) and merges both with
	# contrib/licenses.mjs; cargo-about is not packaged, so a small script
	# reads the same data from `cargo metadata` over the vendored crates.
	pushd rustlib >/dev/null || die
	cargo_env "${CARGO}" metadata --offline --format-version 1 --features gui \
		--filter-platform "$(rust_abi)" > "${T}"/cargo-metadata.json ||
		die "cargo metadata failed"
	popd >/dev/null || die
	"${EPYTHON}" "${FILESDIR}"/obscura-licenses-rust.py \
		< "${T}"/cargo-metadata.json > "${T}"/licenses-rust.json || die

	pushd obscura-ui >/dev/null || die
	# Same allow-list as upstream's "license-node" npm script.
	node node_modules/license-checker/bin/license-checker --start . \
		--onlyAllow "0BSD;Apache-2.0;BSD-2-Clause;BSD-3-Clause;CC0-1.0;CC-BY-3.0;CC-BY-4.0;ISC;Python-2.0;OFL-1.1;MIT" \
		--excludePrivatePackages --unknown --json \
		> "${T}"/licenses-node.json || die "license-checker failed"
	LICENSES_NODE="${T}"/licenses-node.json LICENSES_RUST="${T}"/licenses-rust.json \
		node ../contrib/licenses.mjs > "${T}"/licenses.json || die

	# Upstream's web-linux derivation: `vite build` with the platform and
	# the license JSON in the environment.
	LICENSE_JSON="${T}"/licenses.json OBS_WEB_PLATFORM=linux \
		node node_modules/vite/bin/vite.js build || die "vite build failed"
	popd >/dev/null || die

	# Upstream's gui-gresources derivation.
	pushd rustlib >/dev/null || die
	glib-compile-resources --sourcedir=src/gui \
		--target="${OBSCURA_GRESOURCES_DIR}"/icons.gresource \
		src/gui/icons.gresource.xml || die
	"${EPYTHON}" gen-gresource-xml.py ../obscura-ui/build \
		"${T}"/webui.generated.xml || die
	glib-compile-resources --target="${OBSCURA_GRESOURCES_DIR}"/webui.gresource \
		"${T}"/webui.generated.xml || die

	cargo_src_compile --bin obscura-gui --features gui
	popd >/dev/null || die
}

src_install() {
	local target
	target=rustlib/$(cargo_target_dir) || die
	dobin "${target}"/obscura
	use gui && dobin "${target}"/obscura-gui

	# OpenRC is installed unconditionally, the unit only with USE=systemd.
	newinitd "${FILESDIR}"/obscura.initd obscura
	newconfd "${FILESDIR}"/obscura.confd obscura
	use systemd && systemd_dounit linux/common/obscura.service

	if use gui; then
		domenu linux/common/net.obscura.vpn.gui.desktop
		insinto /usr/share/metainfo
		doins linux/common/net.obscura.vpn.gui.metainfo.xml
		local size
		for size in 64 128 256; do
			newicon -s ${size} linux/common/icons/${size}x${size}/net.obscura.vpn.gui.png \
				net.obscura.vpn.gui.png
		done
	fi

	einstalldocs
}

pkg_postinst() {
	use gui && xdg_pkg_postinst

	elog "Only members of the obscura group may drive the service.  Add a user"
	elog "with:  obscura add-operator <user>  (then log in again)."
	elog
	elog "Start the service with one of:"
	elog "    rc-service obscura start      (and: rc-update add obscura default)"
	elog "    systemctl enable --now obscura.service"
	elog
	elog "On OpenRC without NetworkManager or systemd-resolved, set"
	elog "OBSCURA_DNS=\"disabled\" in /etc/conf.d/obscura, or the service"
	elog "refuses to start (\"no supported DNS manager detected\")."
	if use gui; then
		elog
		elog "The GUI's \"enable/restart service\" repair action calls systemctl;"
		elog "on OpenRC use rc-service/rc-update instead."
	fi
}

pkg_postrm() {
	use gui && xdg_pkg_postrm
}
