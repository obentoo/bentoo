# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE=gst-plugins-base

inherit gstreamer-meson

DESCRIPTION="Opus audio parser plugin for GStreamer"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~mips ppc ppc64 ~riscv ~sparc x86"

COMMON_DEPEND=">=media-libs/opus-1.1:=[${MULTILIB_USEDEP}]"

RDEPEND="${COMMON_DEPEND}
	>=media-libs/gst-plugins-base-${PV}:${SLOT}[${MULTILIB_USEDEP},ogg]
"
DEPEND="${COMMON_DEPEND}"

src_prepare() {
	default
	gstreamer_system_package audio_dep:gstreamer-audio \
		pbutils_dep:gstreamer-pbutils \
		tag_dep:gstreamer-tag
}

# Everything below is for building opusparse from gst-plugins-bad. Once it moves into -base, all below can be removed
SRC_URI+=" https://gstreamer.freedesktop.org/src/gst-plugins-bad/gst-plugins-bad-${PV}.tar.${GST_TARBALL_SUFFIX}"

in_bdir() {
	pushd "${BUILD_DIR}" || die
	"$@"
	popd || die
}

src_configure() {
	S="${WORKDIR}/gst-plugins-base-${PV}" multilib_foreach_abi gstreamer_multilib_src_configure
	# Bentoo: gst-plugins-bad 1.28.3 has an upstream meson bug where
	# tests/check/meson.build:103 references gstmse_private_test_dep, which is
	# only declared in gst-libs/gst/mse/meson.build when -Dmse is enabled.
	# Split-plugin builds (this ebuild) auto-disable mse via the eclass, breaking
	# configure. Force -Dtests=disabled here — RESTRICT="test" (set by the eclass
	# for split plugins) already prevents test execution, so this is consistent.
	S="${WORKDIR}/gst-plugins-bad-${PV}"  multilib_foreach_abi gstreamer_multilib_src_configure -Dtests=disabled
}

src_compile() {
	S="${WORKDIR}/gst-plugins-base-${PV}" multilib_foreach_abi in_bdir gstreamer_multilib_src_compile
	S="${WORKDIR}/gst-plugins-bad-${PV}"  multilib_foreach_abi in_bdir gstreamer_multilib_src_compile
}

src_install() {
	S="${WORKDIR}/gst-plugins-base-${PV}" multilib_foreach_abi in_bdir gstreamer_multilib_src_install
	S="${WORKDIR}/gst-plugins-bad-${PV}"  multilib_foreach_abi in_bdir gstreamer_multilib_src_install
}
