# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CRATES="
	anyhow@1.0.102
	async-broadcast@0.7.2
	async-recursion@1.1.1
	async-trait@0.1.89
	autocfg@1.5.0
	bitflags@2.11.0
	bumpalo@3.20.2
	bytes@1.11.1
	cc@1.2.58
	cfg-if@1.0.4
	concurrent-queue@2.5.0
	crossbeam-utils@0.8.21
	easy_color@0.1.13
	either@1.15.0
	endi@1.1.1
	enumflags2@0.7.12
	enumflags2_derive@0.7.12
	equivalent@1.0.2
	errno@0.3.14
	event-listener-strategy@0.5.4
	event-listener@5.4.1
	fastrand@2.3.0
	find-msvc-tools@0.1.9
	foldhash@0.1.5
	futures-core@0.3.32
	futures-io@0.3.32
	futures-lite@2.6.1
	getrandom@0.2.17
	getrandom@0.4.2
	hashbrown@0.15.5
	hashbrown@0.16.1
	heck@0.5.0
	hex@0.4.3
	hidapi@2.6.5
	id-arena@2.3.0
	indexmap@2.13.0
	itertools@0.14.0
	itoa@1.0.18
	js-sys@0.3.92
	leb128fmt@0.1.0
	libc@0.2.183
	linux-raw-sys@0.12.1
	log@0.4.29
	memchr@2.8.0
	memoffset@0.9.1
	mio@1.2.0
	num_enum@0.7.6
	num_enum_derive@0.7.6
	once_cell@1.21.4
	ordered-stream@0.2.0
	parking@2.2.1
	pin-project-lite@0.2.17
	pkg-config@0.3.32
	ppv-lite86@0.2.21
	prettyplease@0.2.37
	proc-macro-crate@3.5.0
	proc-macro2@1.0.106
	qmk-via-api@0.7.0
	quote@1.0.45
	r-efi@6.0.0
	rand@0.8.5
	rand_chacha@0.3.1
	rand_core@0.6.4
	rustix@1.1.4
	rustversion@1.0.22
	semver@1.0.27
	serde@1.0.228
	serde_core@1.0.228
	serde_derive@1.0.228
	serde_json@1.0.149
	serde_repr@0.1.20
	shlex@1.3.0
	signal-hook-registry@1.4.8
	socket2@0.6.3
	static_assertions@1.1.0
	strum@0.28.0
	strum_macros@0.28.0
	syn@2.0.117
	tempfile@3.27.0
	tokio-macros@2.6.1
	tokio@1.50.0
	toml_datetime@1.1.0+spec-1.1.0
	toml_edit@0.25.8+spec-1.1.0
	toml_parser@1.1.0+spec-1.1.0
	tracing-attributes@0.1.31
	tracing-core@0.1.36
	tracing@0.1.44
	uds_windows@1.2.1
	unicode-ident@1.0.24
	unicode-xid@0.2.6
	uuid@1.23.0
	wasi@0.11.1+wasi-snapshot-preview1
	wasip2@1.0.2+wasi-0.2.9
	wasip3@0.4.0+wasi-0.3.0-rc-2026-01-06
	wasm-bindgen-macro-support@0.2.115
	wasm-bindgen-macro@0.2.115
	wasm-bindgen-shared@0.2.115
	wasm-bindgen@0.2.115
	wasm-encoder@0.244.0
	wasm-metadata@0.244.0
	wasmparser@0.244.0
	windows-link@0.2.1
	windows-sys@0.61.2
	winnow@0.7.15
	winnow@1.0.1
	wit-bindgen-core@0.51.0
	wit-bindgen-rust-macro@0.51.0
	wit-bindgen-rust@0.51.0
	wit-bindgen@0.51.0
	wit-component@0.244.0
	wit-parser@0.244.0
	zbus@5.14.0
	zbus_macros@5.14.0
	zbus_names@4.3.1
	zbus_polkit@5.0.0
	zerocopy-derive@0.8.48
	zerocopy@0.8.48
	zmij@1.0.21
	zvariant@5.10.0
	zvariant_derive@5.10.0
	zvariant_utils@3.3.0
"

RUST_MIN_VERSION="1.87.0"

inherit cargo

DESCRIPTION="Plasma Kameleon kded helper for QMK keyboard LED control"
HOMEPAGE="https://invent.kde.org/plasma/kdeplasma-addons"
SRC_URI="
	mirror://kde/unstable/plasma/${PV}/kdeplasma-addons-${PV}.tar.xz
	${CARGO_CRATE_URIS}
"
S="${WORKDIR}/kdeplasma-addons-${PV}/kdeds/kameleon/qmk/kameleon-qmk-helper"

LICENSE="|| ( LGPL-2.1 LGPL-3 ) CC0-1.0"
# Dependent crate licenses
LICENSE+=" GPL-3 MIT Unicode-3.0 ZLIB"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	sys-auth/polkit
	virtual/libudev:=
"
DEPEND="${RDEPEND}"

src_install() {
	exeinto /usr/libexec/kf6
	doexe target/$(usex debug debug release)/kameleon-qmk-helper

	insinto /usr/share/dbus-1/system.d
	doins org.kde.kameleon.qmk.helper.conf

	insinto /usr/share/polkit-1/actions
	doins org.kde.kameleon.qmk.helper.policy

	sed -e "s|@KDE_INSTALL_FULL_LIBEXECDIR_KF@|/usr/libexec/kf6|" \
		org.kde.kameleon.qmk.helper.service.in \
		> "${T}"/org.kde.kameleon.qmk.helper.service || die
	insinto /usr/share/dbus-1/system-services
	doins "${T}"/org.kde.kameleon.qmk.helper.service

	einstalldocs
}
