# Copyright 2020-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Every crate of two lockfiles: the tdesktop_rust umbrella (tlottie +
# wallet-engine, resolved in src_prepare from wallet-engine's own Cargo.lock)
# and wallet-engine's bindgen/cpp workspace, which generates the C++ binding.
# cargo resolves a whole lockfile before it filters by target or feature, so
# --offline wants every entry present, compiled or not.
CRATES="
	aead@0.5.2
	aes@0.8.4
	android_system_properties@0.1.6
	anstream@1.0.0
	anstyle-parse@1.0.0
	anstyle-query@1.1.5
	anstyle-wincon@3.0.11
	anstyle@1.0.14
	anyhow@1.0.102
	anyhow@1.0.104
	arrayvec@0.7.8
	askama@0.13.1
	askama@0.16.0
	askama_derive@0.13.1
	askama_derive@0.16.0
	askama_macros@0.16.0
	askama_parser@0.13.0
	askama_parser@0.16.0
	async-trait@0.1.89
	autocfg@1.5.1
	base64@0.22.1
	base64ct@1.8.3
	basic-toml@0.1.10
	bitflags@2.13.1
	bitstream-io@4.10.0
	bitvec@1.1.1
	block-buffer@0.10.4
	bnum@0.12.1
	bumpalo@3.20.3
	bytes@1.12.1
	camino@1.2.5
	cargo-platform@0.3.2
	cargo-platform@0.3.3
	cargo_metadata@0.23.1
	cc@1.4.2
	cfg-if@1.0.4
	chrono@0.4.45
	cipher@0.4.4
	clap@4.6.6
	clap_builder@4.6.6
	clap_derive@4.6.4
	clap_lex@1.1.0
	colorchoice@1.0.5
	const-oid@0.9.6
	convert_case@0.11.0
	core-foundation-sys@0.8.7
	cpufeatures@0.2.17
	crc-catalog@2.5.0
	crc@3.4.0
	crypto-common@0.1.7
	crypto_box@0.9.1
	crypto_secretbox@0.1.1
	curve25519-dalek-derive@0.1.1
	curve25519-dalek@4.1.3
	deluxe-core@0.5.0
	deluxe-macros@0.5.0
	deluxe@0.5.0
	der@0.7.10
	digest@0.10.7
	displaydoc@0.2.7
	ed25519-dalek@2.2.0
	ed25519@2.2.3
	equivalent@1.0.2
	errno@0.3.14
	fastnum@0.7.4
	fastrand@2.5.0
	fiat-crypto@0.2.9
	find-msvc-tools@0.1.10
	form_urlencoded@1.2.2
	fs-err@3.3.1
	funty@2.0.0
	futures-channel@0.3.34
	futures-core@0.3.34
	futures-executor@0.3.34
	futures-io@0.3.34
	futures-macro@0.3.34
	futures-sink@0.3.34
	futures-task@0.3.34
	futures-util@0.3.34
	futures@0.3.31
	generic-array@0.14.7
	getrandom@0.2.17
	getrandom@0.3.4
	getrandom@0.4.3
	glob@0.3.4
	goblin@0.8.2
	hashbrown@0.17.1
	heck@0.4.1
	heck@0.5.0
	hex@0.4.3
	hmac@0.12.1
	iana-time-zone-haiku@0.1.2
	iana-time-zone@0.1.65
	icu_collections@2.2.0
	icu_locale_core@2.2.0
	icu_normalizer@2.2.0
	icu_normalizer_data@2.2.0
	icu_properties@2.2.0
	icu_properties_data@2.2.0
	icu_provider@2.2.0
	idna@1.1.0
	idna_adapter@1.2.2
	if_chain@1.0.3
	indexmap@2.14.0
	inout@0.1.4
	is_terminal_polyfill@1.70.2
	itoa@1.0.18
	js-sys@0.3.104
	libc@0.2.189
	libm@0.2.16
	linux-raw-sys@0.12.1
	litemap@0.8.2
	lock_api@0.4.14
	log@0.4.33
	memchr@2.8.3
	minimal-lexical@0.2.1
	no_std_io2@0.9.4
	nom@7.1.3
	num-bigint@0.4.8
	num-integer@0.1.47
	num-traits@0.2.19
	once_cell@1.21.4
	once_cell_polyfill@1.70.2
	opaque-debug@0.3.1
	ordered-float@2.10.1
	parking_lot@0.12.5
	parking_lot_core@0.9.12
	password-hash@0.5.0
	paste@1.0.15
	pbkdf2@0.12.2
	percent-encoding@2.3.2
	pin-project-lite@0.2.17
	pkcs8@0.10.2
	plain@0.2.3
	poly1305@0.8.0
	potential_utf@0.1.5
	proc-macro-crate@1.3.1
	proc-macro-crate@3.5.0
	proc-macro2@1.0.107
	quote@1.0.47
	r-efi@5.3.0
	r-efi@6.0.0
	radium@0.7.0
	rand_core@0.6.4
	redox_syscall@0.5.18
	rustc-hash@2.1.3
	rustc_version@0.4.1
	rustix@1.1.4
	rustversion@1.0.23
	salsa20@0.10.2
	scopeguard@1.2.0
	scroll@0.12.0
	scroll_derive@0.12.1
	semver@1.0.28
	serde-aux@4.7.0
	serde-value@0.7.0
	serde@1.0.229
	serde_core@1.0.229
	serde_derive@1.0.229
	serde_json@1.0.151
	serde_spanned@1.1.1
	sha2@0.10.9
	shlex@2.0.1
	signature@2.2.0
	siphasher@1.0.3
	slab@0.4.12
	smallvec@1.15.2
	smawk@0.3.3
	spki@0.7.3
	stable_deref_trait@1.2.1
	static_assertions@1.1.0
	strsim@0.10.0
	strsim@0.11.1
	subtle@2.6.1
	syn@2.0.119
	syn@3.0.3
	synstructure@0.13.2
	tap@1.0.1
	tempfile@3.27.0
	textwrap@0.16.2
	thiserror-impl@2.0.17
	thiserror-impl@2.0.20
	thiserror@2.0.17
	thiserror@2.0.20
	tinystr@0.8.3
	toml@1.1.4+spec-1.1.0
	toml_datetime@0.6.11
	toml_datetime@1.1.1+spec-1.1.0
	toml_edit@0.19.15
	toml_edit@0.25.13+spec-1.1.0
	toml_parser@1.1.3+spec-1.1.0
	toml_writer@1.1.2+spec-1.1.0
	ton_core@0.1.4
	ton_macros@0.1.2
	topological-sort@0.2.2
	typenum@1.20.1
	unicode-ident@1.0.24
	unicode-linebreak@0.1.5
	unicode-segmentation@1.13.3
	unicode-width@0.2.2
	uniffi@0.32.0
	uniffi_bindgen@0.32.0
	uniffi_core@0.32.0
	uniffi_internal_macros@0.32.0
	uniffi_macros@0.32.0
	uniffi_meta@0.32.0
	uniffi_pipeline@0.32.0
	uniffi_udl@0.32.0
	universal-hash@0.5.1
	url@2.5.7
	utf8_iter@1.0.4
	utf8parse@0.2.2
	version_check@0.9.5
	wasi@0.11.1+wasi-snapshot-preview1
	wasip2@1.0.4+wasi-0.2.12
	wasm-bindgen-macro-support@0.2.127
	wasm-bindgen-macro@0.2.127
	wasm-bindgen-shared@0.2.127
	wasm-bindgen@0.2.127
	weedle2@5.0.0
	windows-core@0.62.2
	windows-implement@0.60.2
	windows-interface@0.59.3
	windows-link@0.2.1
	windows-result@0.4.1
	windows-strings@0.5.1
	windows-sys@0.61.2
	winnow@0.5.40
	winnow@0.7.15
	winnow@1.0.4
	wit-bindgen@0.57.1
	writeable@0.6.3
	wyz@0.5.1
	yoke-derive@0.8.2
	yoke@0.8.3
	zerofrom-derive@0.1.7
	zerofrom@0.1.8
	zeroize@1.9.0
	zeroize_derive@1.5.0
	zerotrie@0.2.4
	zerovec-derive@0.11.3
	zerovec@0.11.6
	zmij@1.0.23
"

PYTHON_COMPAT=( python3_{12..15} )
# The toolchain tdesktop builds tdesktop_rust with (prepare.py rustToolchain,
# centos_env Dockerfile RUST_TOOLCHAIN), and wallet-engine's own rust-version.
RUST_MIN_VER="1.96.1"

# BENTOO-DIVERGENCE: INHERIT - cargo, for tdesktop_rust (tlottie + wallet-engine),
# which the 7.3 series builds from source next to Telegram; ::gentoo is on 7.1.
# BENTOO-DIVERGENCE: IUSE - "debug" comes with cargo.eclass and is inert here:
# tdesktop_rust_build always passes --release.
# BENTOO-DIVERGENCE: DEFINED_PHASES - src_unpack, because cargo_src_unpack
# would feed the wallet-engine patch to unpack().
inherit xdg cargo cmake python-any-r1 optfeature flag-o-matic

DESCRIPTION="Official desktop client for Telegram"
HOMEPAGE="https://desktop.telegram.org https://github.com/telegramdesktop/tdesktop"

MY_P="tdesktop-${PV}-full"
# NOT the newest commits.  The 7.3 series links ONE Rust staticlib,
# tdesktop_rust, that upstream assembles outside the source tarball from two
# pinned checkouts (Telegram/build/docker/centos_env/Dockerfile, stage
# tdesktop_rust; same pins in Telegram/build/prepare/prepare.py) plus a patch
# from desktop-app/patches at the revision prepare.py's stage('patches') pins.
# Re-read all three on every bump.
TLOTTIE_COMMIT="92df98dc209bc39b1e567ec74a8c86a0af5239de"
WALLET_ENGINE_COMMIT="e59e0d89d7ee90c388bf36e3334c5b276f396697"
PATCHES_COMMIT="aec474953ff7ee9b6e4cd9b8658288ea86d124f3"
SRC_URI="
	https://github.com/telegramdesktop/tdesktop/releases/download/v${PV}/${MY_P}.tar.gz
	https://github.com/dkaraush/tlottie/archive/${TLOTTIE_COMMIT}.tar.gz
		-> tlottie-${TLOTTIE_COMMIT:0:10}.tar.gz
	https://github.com/i582/wallet-engine/archive/${WALLET_ENGINE_COMMIT}.tar.gz
		-> wallet-engine-${WALLET_ENGINE_COMMIT:0:10}.tar.gz
	https://raw.githubusercontent.com/desktop-app/patches/${PATCHES_COMMIT}/wallet-engine.patch
		-> ${PN}-wallet-engine-${PATCHES_COMMIT:0:10}.patch
	${CARGO_CRATE_URIS}
"
S="${WORKDIR}/${MY_P}"

LICENSE="BSD GPL-3-with-openssl-exception LGPL-2+"
# BENTOO-DIVERGENCE: LICENSE - tlottie, wallet-engine and the crates linked
# into the tdesktop_rust archive, all new in 7.3.
# tlottie is MIT; wallet-engine and its vendored ton crate are MIT OR Apache-2.0.
LICENSE+=" MIT || ( MIT Apache-2.0 )"
# Dependent crate licenses (the umbrella only: the bindgen crates run at build
# time and are not linked into Telegram)
LICENSE+=" BSD MIT MPL-2.0 Unicode-3.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="dbus enchant +fonts screencast wayland webkit +X"

# BENTOO-DIVERGENCE: DEPEND - series 7.2 adds cmark-gfm and glibmm through
# CDEPEND below; ::gentoo is on 7.1, whose dep set predates both.  Since 7.3,
# tlottie is no longer media-libs/tlottie: it is built here, inside the
# tdesktop_rust archive, together with wallet-engine.
# BENTOO-DIVERGENCE: RDEPEND - same CDEPEND, same reason.
CDEPEND="
	!net-im/telegram-desktop-bin
	app-arch/lz4:=
	app-text/cmark-gfm:=
	dev-cpp/abseil-cpp:=
	dev-cpp/ada:=
	dev-cpp/cld3:=
	>=dev-cpp/glibmm-2.77:2.68
	dev-cpp/toomanycooks
	dev-libs/glib:2
	dev-libs/libfido2:=
	dev-libs/openssl:=
	>=dev-libs/protobuf-21.12
	dev-libs/qr-code-generator:=
	dev-libs/xxhash
	>=dev-qt/qtbase-6.5:6=[dbus?,gui,network,opengl,ssl,wayland?,widgets]
	>=dev-qt/qtimageformats-6.5:6
	>=dev-qt/qtsvg-6.5:6
	kde-frameworks/kcoreaddons:6
	media-libs/libjpeg-turbo:=
	media-libs/openal
	media-libs/opus
	media-libs/rnnoise
	>=media-libs/tg_owt-0_pre20241202:=[screencast=,X=]
	>=media-video/ffmpeg-6:=[opus,vpx]
	net-libs/tdlib:=[tde2e]
	sys-apps/hwloc:=
	virtual/minizip:=
	!enchant? ( >=app-text/hunspell-1.7:= )
	enchant? ( app-text/enchant:= )
	webkit? ( wayland? (
		>=dev-qt/qtdeclarative-6.5:6
		>=dev-qt/qtwayland-6.5:6[compositor(+),qml]
	) )
"
RDEPEND="${CDEPEND}
	webkit? ( || ( net-libs/webkit-gtk:4.1 net-libs/webkit-gtk:6 ) )
"
DEPEND="${CDEPEND}
	>=dev-cpp/cppgir-2.0_p20240315
	dev-cpp/expected
	dev-cpp/expected-lite
	>=dev-cpp/ms-gsl-4.1.0
	dev-cpp/range-v3
"
# BENTOO-DIVERGENCE: BDEPEND - gobject-introspection floor required by 7.2.
BDEPEND="
	${PYTHON_DEPS}
	>=dev-build/cmake-3.16
	>=dev-cpp/cppgir-2.0_p20260226
	>=dev-libs/gobject-introspection-1.82.0-r2
	dev-qt/qtshadertools
	>=dev-util/gdbus-codegen-2.80.5-r1
	virtual/pkgconfig
	wayland? ( dev-util/wayland-scanner )
"
# NOTE: dev-cpp/expected-lite used indirectly by a dev-cpp/cppgir header file
# NOTE: sys-apps/hwloc is depended upon by dev-cpp/toomanycooks, but needs to
#       cause SLOT rebuilds here, as dev-cpp/toomanycooks is header-only

PATCHES=(
	"${FILESDIR}"/tdesktop-5.7.2-cstring.patch
	"${FILESDIR}"/tdesktop-5.8.3-cstdint.patch
	"${FILESDIR}"/tdesktop-5.14.3-system-cppgir.patch
)

pkg_pretend() {
	if [[ ${MERGE_TYPE} != binary ]]; then
		if has ccache ${FEATURES}; then
			ewarn "ccache does not work with ${PN} out of the box"
			ewarn "due to usage of precompiled headers"
			ewarn "check bug https://bugs.gentoo.org/715114 for more info"
			ewarn
		fi
	fi
}

pkg_setup() {
	# Both eclasses export pkg_setup and only the last inherited one would
	# run; without rust_pkg_setup, ${CARGO} and the Rust slot are never set.
	rust_pkg_setup
	python-any-r1_pkg_setup
}

src_unpack() {
	# cargo_src_unpack would hand the wallet-engine patch to unpack(), which
	# does not know the format; take everything else the same way it does.
	local archive
	for archive in ${A}; do
		case ${archive} in
			*.crate|*.patch) ;;
			*) unpack "${archive}" ;;
		esac
	done
	cargo_crate_unpack
	cargo_gen_config
}

src_prepare() {
	# tdesktop_rust, the way centos_env/Dockerfile builds it: wallet-engine
	# patched with desktop-app/patches' wallet-engine.patch (no tlottie.patch
	# any more since 7.3), and a two-line umbrella crate re-exporting both.
	# One crate on purpose: each Rust staticlib carries its own copy of std,
	# so two archives would define the same runtime symbols twice and the
	# link would fail.
	pushd "${WORKDIR}/wallet-engine-${WALLET_ENGINE_COMMIT}" >/dev/null || die
	eapply "${DISTDIR}/${PN}-wallet-engine-${PATCHES_COMMIT:0:10}.patch"
	popd >/dev/null || die

	local umbrella="${WORKDIR}/tdesktop_rust"
	mkdir -p "${umbrella}/src" || die
	cat > "${umbrella}/Cargo.toml" <<-EOF || die
		[package]
		name = "tdesktop_rust"
		version = "0.1.0"
		edition = "2024"

		[dependencies]
		tlottie = { path = "../tlottie-${TLOTTIE_COMMIT}", features = ["c-api"] }
		wallet-engine = { path = "../wallet-engine-${WALLET_ENGINE_COMMIT}" }
	EOF
	printf 'pub use ::tlottie;\npub use ::wallet_engine;\n' \
		> "${umbrella}/src/lib.rs" || die
	# Upstream runs `cargo add`, which resolves from scratch.  Seeding the
	# lock with wallet-engine's own keeps every version it pins; cargo then
	# only adds tlottie and prunes what the umbrella does not use -- the
	# same set CRATES above was generated from.
	cp "${WORKDIR}/wallet-engine-${WALLET_ENGINE_COMMIT}/Cargo.lock" \
		"${umbrella}/" || die

	# Happily fail if libraries aren't found...
	find -type f \( -name 'CMakeLists.txt' -o -name '*.cmake' \) \
		\! -path './cmake/external/qt/package.cmake' \
		-print0 | xargs -0 sed -i \
		-e '/pkg_check_modules(/s/[^ ]*)/REQUIRED &/' \
		-e '/find_package(/s/)/ REQUIRED)/' \
		-e '/find_library(/s/)/ REQUIRED)/' \
		-e '/find_path(/s/)/ REQUIRED)/' || die
	# Make sure to check the excluded files for new
	# CMAKE_DISABLE_FIND_PACKAGE/CMAKE_REQUIRE_FIND_PACKAGE entries.

	# Some packages are found through pkg_check_modules, rather than find_package
	sed -e '/find_package(lz4 /d' -i cmake/external/lz4/CMakeLists.txt || die
	sed -e '/find_package(Opus /d' -i cmake/external/opus/CMakeLists.txt || die
	sed -e '/find_package(xxHash /d' -i cmake/external/xxhash/CMakeLists.txt || die
	sed -e '/find_package(cmark-gfm\(-extensions\)\? /d' \
		-i cmake/external/cmark_gfm/CMakeLists.txt || die

	# Temporary workaround for https://bugs.gentoo.org/977603
	sed -e '/find_package(minizip /d' \
		-i cmake/external/minizip/CMakeLists.txt || die

	# Greedily remove ThirdParty directories, keep only ones that interest us
	local keep=(
		cmark-gfm  # Upstream dropped the packaged/system code path
		libprisma  # Telegram-specific library, no stable releases
		tgcalls  # Telegram-specific library, no stable releases
		xdg-desktop-portal  # Only a few xml files are used with gdbus-codegen
		MicroTeX  # Telegram-specific fork, no stable releases
		zxcvbn  # 7.3: built in, no packaged branch (Telegram/cmake/lib_zxcvbn.cmake)
	)
	for x in Telegram/ThirdParty/*; do
		has "${x##*/}" "${keep[@]}" || rm -r "${x}" || die
	done

	# Control libdispatch dependency from here, as there's no
	# CMAKE_DISABLE_FIND_PACKAGE for find_library
	: > cmake/external/dispatch/CMakeLists.txt || die

	# Control QtDBus dependency from here, to avoid messing with QtGui.
	# QtGui will use find_package to find QtDbus as well, which
	# conflicts with the -DCMAKE_DISABLE_FIND_PACKAGE method.
	if ! use dbus; then
		sed -e '/find_package(Qt[^ ]* OPTIONAL_COMPONENTS/s/DBus *//' \
			-i cmake/external/qt/package.cmake || die
	fi

	# Control automagic dep only needed when USE="webkit wayland"
	if ! use webkit || ! use wayland; then
		sed -e 's/QT_CONFIG(wayland_compositor_quick)/0/' \
			-i Telegram/lib_webview/webview/platform/linux/webview_linux_compositor.h || die
	fi

	# Shut the CMake 4 QA checker up by removing unused CMakeLists files
	rm cmake/external/glib/cppgir/expected-lite/example/CMakeLists.txt || die
	rm cmake/external/glib/cppgir/expected-lite/test/CMakeLists.txt || die
	rm cmake/external/glib/cppgir/expected-lite/CMakeLists.txt || die

	cmake_src_prepare
}

tdesktop_rust_build() {
	local umbrella="${WORKDIR}/tdesktop_rust"
	local out="${WORKDIR}/tdesktop_rust-out"
	local wallet="${WORKDIR}/wallet-engine-${WALLET_ENGINE_COMMIT}"
	local tlottie="${WORKDIR}/tlottie-${TLOTTIE_COMMIT}"
	# Not cargo_target_dir: it follows USE=debug (which cargo.eclass adds to
	# IUSE), while this archive is always built --release, as upstream does.
	local rel="${umbrella}/target/release"
	mkdir -p "${out}"/{lib,include/tlottie,include/wallet_engine} || die

	pushd "${umbrella}" >/dev/null || die
	# upstream's Linux recipe (centos_env/Dockerfile) with its non-MINSIZE
	# opt-level.  Both crate types on purpose: the staticlib is what Telegram
	# links, the cdylib is what the bindgen reads UniFFI metadata from.
	# --locked cannot be used: the lock was seeded in src_prepare and cargo
	# still has to add tlottie to it (offline, from the vendored CRATES).
	cargo_env "${CARGO}" rustc --lib --release --offline \
		--crate-type staticlib --crate-type cdylib \
		--config "profile.release.opt-level=3" \
		--config "profile.release.lto='thin'" \
		--config "profile.release.codegen-units=1" \
		--config "profile.release.panic='unwind'" \
		-- --print native-static-libs || die "cargo rustc tdesktop_rust failed"
	popd >/dev/null || die

	cp "${rel}/libtdesktop_rust.a" "${out}/lib/" || die
	cp "${tlottie}/include/tlottie.h" "${out}/include/tlottie/" || die

	# wallet-engine's own uniffi-bindgen-cpp, pinned by its Cargo.lock.  On
	# Linux the generated wallet_engine.cpp stays next to the header:
	# cmake/external/wallet_engine reads it from the include directory.
	# It runs `cargo metadata` in the current directory to map the library
	# back to its crates, so it has to start inside the umbrella, exactly
	# where upstream runs it.
	pushd "${umbrella}" >/dev/null || die
	CARGO_TARGET_DIR="${WORKDIR}/bindgen-target" cargo_env "${CARGO}" run \
		--release --offline --locked \
		--manifest-path "${wallet}/bindgen/cpp/bindgen/Cargo.toml" -- \
		--library --out-dir "${out}/include/wallet_engine" \
		"${rel}/libtdesktop_rust.so" || die "wallet-engine bindgen failed"
	popd >/dev/null || die
	[[ -f ${out}/include/wallet_engine/wallet_engine.hpp &&
		-f ${out}/include/wallet_engine/wallet_engine.cpp ]] ||
		die "bindgen produced no wallet_engine.{hpp,cpp}"
}

src_configure() {
	tdesktop_rust_build

	# Having user paths sneak into the build environment through the
	# XDG_DATA_DIRS variable causes all sorts of weirdness with cppgir:
	# - bug 909038: can't read from flatpak directories (fixed upstream)
	# - bug 920819: system-wide directories ignored when variable is set
	export XDG_DATA_DIRS="${ESYSROOT}/usr/share"

	# Evil flag (See https://bugs.gentoo.org/919201)
	filter-flags -fno-delete-null-pointer-checks

	# The ABI of media-libs/tg_owt breaks if the -DNDEBUG flag doesn't keep
	# the same state across both projects.
	# See https://bugs.gentoo.org/866055
	append-cppflags -DNDEBUG

	local no_webkit_wayland=$(use webkit && use wayland && echo no || echo yes)
	local use_webkit_wayland=$(use webkit && use wayland && echo yes || echo no)
	local mycmakeargs=(
		-DQT_VERSION_MAJOR=6

		# Override new cmake.eclass defaults (https://bugs.gentoo.org/921939)
		# Upstream never tests this any other way
		-DCMAKE_DISABLE_PRECOMPILE_HEADERS=OFF

		# Control automagic dependencies on certain packages
		## These libraries are only used in lib_webview, for wayland
		## See Telegram/lib_webview/webview/platform/linux/webview_linux_compositor.h
		-DCMAKE_DISABLE_FIND_PACKAGE_Qt6Quick=${no_webkit_wayland}
		-DCMAKE_DISABLE_FIND_PACKAGE_Qt6QuickWidgets=${no_webkit_wayland}
		-DCMAKE_DISABLE_FIND_PACKAGE_Qt6WaylandCompositor=${no_webkit_wayland}

		# Make sure dependencies that aren't patched to be REQUIRED in
		# src_prepare, are found.  This was suggested to me by the telegram
		# devs, in lieu of having explicit flags in the build system.
		-DCMAKE_REQUIRE_FIND_PACKAGE_Qt6DBus=$(usex dbus)
		-DCMAKE_REQUIRE_FIND_PACKAGE_Qt6Quick=${use_webkit_wayland}
		-DCMAKE_REQUIRE_FIND_PACKAGE_Qt6QuickWidgets=${use_webkit_wayland}
		-DCMAKE_REQUIRE_FIND_PACKAGE_Qt6WaylandCompositor=${use_webkit_wayland}

		-DDESKTOP_APP_DISABLE_QT_PLUGINS=ON
		## Enables enchant and disables hunspell
		-DDESKTOP_APP_USE_ENCHANT=$(usex enchant)
		## Use system fonts instead of bundled ones
		-DDESKTOP_APP_USE_PACKAGED_FONTS=$(usex !fonts)

		# Point the three lookups at what tdesktop_rust_build produced.
		# Setting the cache variables makes find_library/find_path skip the
		# search, so the REQUIRED the src_prepare sed adds is satisfied
		# instead of failing on a library that is never installed.
		-DDESKTOP_APP_TDESKTOP_RUST_LIBRARY="${WORKDIR}/tdesktop_rust-out/lib/libtdesktop_rust.a"
		-DDESKTOP_APP_TLOTTIE_INCLUDE_DIR="${WORKDIR}/tdesktop_rust-out/include/tlottie"
		-DDESKTOP_APP_WALLET_ENGINE_INCLUDE_DIR="${WORKDIR}/tdesktop_rust-out/include/wallet_engine"
	)

	if [[ -n ${MY_TDESKTOP_API_ID} && -n ${MY_TDESKTOP_API_HASH} ]]; then
		einfo "Found custom API credentials"
		mycmakeargs+=(
			-DTDESKTOP_API_ID="${MY_TDESKTOP_API_ID}"
			-DTDESKTOP_API_HASH="${MY_TDESKTOP_API_HASH}"
		)
	else
		# https://github.com/telegramdesktop/tdesktop/blob/dev/snap/snapcraft.yaml
		# Building with snapcraft API credentials by default
		# Custom API credentials can be obtained here:
		# https://github.com/telegramdesktop/tdesktop/blob/dev/docs/api_credentials.md
		# After getting credentials you can export variables:
		#  export MY_TDESKTOP_API_ID="17349""
		#  export MY_TDESKTOP_API_HASH="344583e45741c457fe1862106095a5eb"
		# and restart the build"
		# you can set above variables (without export) in /etc/portage/env/net-im/telegram-desktop
		# portage will use custom variable every build automatically
		mycmakeargs+=(
			-DTDESKTOP_API_ID="611335"
			-DTDESKTOP_API_HASH="d524b414d21f4d37f08684c1df41ac9c"
		)
	fi

	cmake_src_configure
}

src_compile() {
	# The cppgir program causes the gen/gio/_types.hpp file to be updated.
	# Since this program can usually be invoked anywhere in the build process,
	# running it *after* some files depending on the header have been compiled
	# causes Telegram to be linked again during src_install().  This is a slow
	# process (especially with LTO), so we try to avoid it by running all
	# cppgir targets upfront.
	cmake_build $("${CMAKE_BINARY}" --build "${BUILD_DIR}" -t help | sed -n '/^[^/]*_cppgir:/s/:.*//p')
	cmake_build
	cmake_build  # Just in case, should say "no work to do"
}

pkg_postinst() {
	xdg_pkg_postinst
	if ! use X && ! use screencast; then
		ewarn "both the 'X' and 'screencast' USE flags are disabled, screen sharing won't work!"
		ewarn
	fi
	optfeature_header
	optfeature "AVIF, HEIF and JpegXL image support" kde-frameworks/kimageformats:6[avif,heif,jpegxl]
}
