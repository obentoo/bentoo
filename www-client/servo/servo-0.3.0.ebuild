# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# NOTE: Servo is a Cargo *virtual workspace* with ~1000 crate dependencies and a
# bundled copy of SpiderMonkey (mozjs_sys, ~165 MiB of C++) that is compiled from
# source by mozjs-sys' build.rs. Instead of enumerating every crate in CRATES=""
# (which would trip Portage's "very large number of CRATES" QA notice), we consume
# upstream's official *vendored* source tarball published with each release:
#   servo-vX.Y.Z-src-vendored.tar.gz
# It ships a complete vendor/ directory plus an in-tree .cargo/config.toml that
# points cargo at it (source.vendored-sources -> vendor/). At v0.3.0 the Cargo.lock
# has ZERO git+ sources and the [patch.crates-io] section is entirely commented out,
# so no GIT_CRATES declarations are required.
#
# We do NOT use cargo.eclass' CRATES/cargo_gen_config machinery, because that would
# overwrite the in-tree vendored config. We inherit cargo only for its
# cargo_target_dir / RUSTFLAGS / RUST_MIN_VER plumbing and drive the build offline.

RUST_MIN_VER="1.96.0"
RUST_MAX_VER="1.96.0"

inherit cargo desktop multiprocessing xdg

DESCRIPTION="A web browser engine written in Rust (servoshell tech demo)"
HOMEPAGE="https://servo.org/ https://github.com/servo/servo"

SRC_URI="https://github.com/servo/servo/releases/download/v${PV}/servo-v${PV}-src-vendored.tar.gz
	-> ${P}-src-vendored.tar.gz"
S="${WORKDIR}"

# Servo itself is MPL-2.0. The vendored crates and the bundled SpiderMonkey carry
# a mix of permissive licenses; this LICENSE list mirrors what upstream's about.toml
# and the vendor/ tree contain.
LICENSE="MPL-2.0"
LICENSE+="
	|| ( Apache-2.0 Boost-1.0 ) Apache-2.0 Apache-2.0-with-LLVM-exceptions
	BSD BSD-2 Boost-1.0 BZIP2 CC0-1.0 ISC LGPL-2.1+ MIT MPL-2.0
	openssl Unicode-3.0 Unicode-DFS-2016 ZLIB
"
SLOT="0"
KEYWORDS="-* ~amd64"

IUSE="+gstreamer"

# System dependencies derived from upstream python/servo/platform/linux_packages
# (apt_common.txt + dnf_base.txt) cross-mapped to Gentoo packages. mozjs_sys builds
# SpiderMonkey from source, so it needs clang/llvm at build time. gstreamer enables
# the servo/media-gstreamer feature (HTML media playback); it is OFF by default
# upstream (default features do not include media-gstreamer).
DEPEND="
	dev-libs/glib:2
	media-libs/fontconfig
	media-libs/freetype:2
	media-libs/harfbuzz:=
	media-libs/libglvnd
	media-libs/mesa
	media-libs/vulkan-loader
	sys-apps/dbus
	virtual/zlib:=
	virtual/libudev:=
	x11-libs/libX11
	x11-libs/libXcursor
	x11-libs/libXi
	x11-libs/libXmu
	x11-libs/libXrandr
	x11-libs/libxcb:=
	x11-libs/libxkbcommon
	gstreamer? (
		media-libs/gst-plugins-base:1.0
		media-libs/gstreamer:1.0
	)
"
RDEPEND="${DEPEND}"
BDEPEND="
	>=virtual/rust-${RUST_MIN_VER}
	dev-util/gperf
	llvm-core/clang
	llvm-core/llvm
	virtual/pkgconfig
"

# rust does not use *FLAGS from make.conf, silence portage warning
QA_FLAGS_IGNORED="usr/bin/servoshell"

src_unpack() {
	# Plain tarball; do not use cargo_src_unpack (it would ignore the vendored
	# config and try to re-vendor from CRATES).
	default
}

src_prepare() {
	default

	# Point cargo at the in-tree vendored config explicitly. The shipped
	# .cargo/config.toml uses a relative `directory = "vendor/"`, which only
	# resolves when cargo's CWD is ${S}; making the path absolute is safer.
	sed -i "s|directory = \"vendor/\"|directory = \"${S}/vendor\"|" \
		"${S}/.cargo/config.toml" || die
}

src_compile() {
	local features="--no-default-features"
	# Mirror upstream default features for servoshell, toggling media-gstreamer
	# via the gstreamer USE flag.
	local feat="baked-in-resources,gamepad,servo/clipboard,js_jit,max_log_level,webgpu,webxr"
	use gstreamer && feat+=",media-gstreamer"

	# mozjs_sys compiles SpiderMonkey from source via clang/llvm. RUSTC_BOOTSTRAP
	# is required because servo uses nightly-only -Z/feature flags gated behind it
	# (see .cargo/config.toml: RUSTC_BOOTSTRAP=crown,script,...).
	export RUSTC_BOOTSTRAP="crown,script,script_bindings,style_tests,mozjs,mozjs_sys"
	export CARGO_HOME="${ECARGO_HOME}"

	CARGO_NET_OFFLINE=true \
	cargo build --release --offline \
		--manifest-path "${S}/Cargo.toml" \
		-p servoshell ${features} --features "${feat}" \
		-j "$(makeopts_jobs)" || die "cargo build failed"
}

src_install() {
	dobin "${S}/target/release/servoshell"

	# servoshell bakes resources into the binary (baked-in-resources feature),
	# so no runtime resource directory needs to be installed.
	newicon -s 64 resources/servo_64.png servo.png

	# Upstream's org.servo.Servo.desktop ships with a comment header and
	# SERVO_SRC_PATH placeholders that make it an invalid desktop entry; rewrite
	# Exec to the installed binary and drop everything before [Desktop Entry].
	sed -e '0,/^\[Desktop Entry\]/{/^\[Desktop Entry\]/!d}' \
		-e 's|SERVO_SRC_PATH/target/release/servoshell|servoshell|g' \
		-e '/^# TODO:/d' \
		resources/org.servo.Servo.desktop > "${T}/org.servo.Servo.desktop" || die
	domenu "${T}/org.servo.Servo.desktop"

	dodoc README.md
}
