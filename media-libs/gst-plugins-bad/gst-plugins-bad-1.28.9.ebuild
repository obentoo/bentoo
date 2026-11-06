# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE="gst-plugins-bad"
# BENTOO-DIVERGENCE: INHERIT - no virtualx in this ebuild's inherit line, where
# ::gentoo lists it. Cosmetic, and checked rather than assumed: gstreamer-meson
# .eclass does "inherit virtualx" itself, in the branch taken by a top-level
# module (not a split plugin), on both sides. virtualx appears in _eclasses_ of
# both md5-cache entries, so the same eclass is loaded either way - ::gentoo
# simply restates in the ebuild what its eclass already did.
# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo carries four GStreamer security patches (SA-2026-0013,
# -0014, -0015, -0017) plus respect-webrtcdsp-disable. Those are
# backports onto THEIR 1.26.11; upstream shipped the same fixes in the series
# this ebuild tracks. Verified 2026-09-07 rather than assumed: all but -0014 reverse-apply cleanly
# against the 1.28.6 tarball, and -0014's (guint64) cast is present in both
# gstav1parser.c and gstav1parse.c, whose _read_leb128 already takes a size.
inherit gstreamer-meson verify-sig

DESCRIPTION="Less plugins for GStreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"
SRC_URI+=" verify-sig? ( https://gstreamer.freedesktop.org/src/${GST_ORG_MODULE}/${GST_ORG_MODULE}-${PV}.tar.xz.asc )"

LICENSE="LGPL-2"
KEYWORDS="~alpha amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ppc64 ~riscv ~sparc x86"

IUSE="X bzip2 +introspection +orc udev vaapi vnc vulkan wayland"
REQUIRED_USE="vulkan? ( || ( X wayland ) )"

# BENTOO-DIVERGENCE: RDEPEND - no !media-plugins/gst-plugins-va blocker.
# ::gentoo REMOVED media-plugins/gst-plugins-va and blocks whatever copy a
# user still has installed. bentoo kept the package: the VA plugin is carved
# out of this tarball in src_install and pulled back in through PDEPEND below,
# so the blocker would refuse to install what this ebuild itself asks for.
# BENTOO-DIVERGENCE: DEPEND - same blocker, reached through DEPEND="${RDEPEND}".

# X11 is automagic for now, upstream #709530 - only used by librfb USE=vnc plugin
# Baseline requirement for libva is 1.6, but 1.15 gets more features
RDEPEND="
	!media-plugins/gst-transcoder

	>=media-libs/gstreamer-${PV}:${SLOT}[${MULTILIB_USEDEP},introspection?]
	>=media-libs/gst-plugins-base-${PV}:${SLOT}[${MULTILIB_USEDEP},introspection?]
	introspection? ( >=dev-libs/gobject-introspection-1.82.0-r2:= )

	bzip2? ( >=app-arch/bzip2-1.0.6-r4[${MULTILIB_USEDEP}] )
	vnc? ( X? ( x11-libs/libX11[${MULTILIB_USEDEP}] ) )
	vulkan? (
		media-libs/vulkan-loader[${MULTILIB_USEDEP}]
		X? (
			x11-libs/libxcb:=[${MULTILIB_USEDEP}]
			x11-libs/libxkbcommon[${MULTILIB_USEDEP}]
		)
	)
	wayland? (
		>=dev-libs/wayland-1.4.0[${MULTILIB_USEDEP}]
		>=x11-libs/libdrm-2.4.98[${MULTILIB_USEDEP}]
		>=dev-libs/wayland-protocols-1.26
	)

	orc? ( >=dev-lang/orc-0.4.33[${MULTILIB_USEDEP}] )

	vaapi? (
		>=media-libs/libva-1.15:=[${MULTILIB_USEDEP}]
		udev? ( dev-libs/libgudev[${MULTILIB_USEDEP}] )
	)
"
DEPEND="${RDEPEND}"
# gst-plugins-va listed in PDEPEND to avoid circular dependency with gst-plugins-bad
PDEPEND="vaapi? ( >=media-plugins/gst-plugins-va-${PV}:${SLOT}[${MULTILIB_USEDEP}] )"
BDEPEND="
	dev-util/glib-utils
	wayland? ( dev-util/wayland-scanner )
"

DOCS=( README.md )

BDEPEND+=" verify-sig? ( sec-keys/openpgp-keys-tpm )"
VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/tpm.asc

src_prepare() {
	default
	addpredict /dev # Prevent sandbox violations bug #570624
}

multilib_src_configure() {
	GST_PLUGINS_NOAUTO="bz2 hls ipcpipeline lcevcdecoder lcevcencoder librfb shm va vulkan wayland"

	local emesonargs=(
		-Dshm=enabled
		-Dipcpipeline=enabled
		-Dhls=disabled
		-Dlcevcdecoder=disabled
		-Dlcevcencoder=disabled

		$(meson_feature bzip2 bz2)
		$(meson_feature vaapi va)
		$(meson_feature vulkan)
		$(meson_feature vulkan vulkan-video)
		-Dudev=$(usex udev $(usex vaapi enabled disabled) disabled)
		$(meson_feature vnc librfb)
		-Dx11=$(usex X $(usex vnc enabled disabled) disabled)
		$(meson_feature wayland)
	)

	if use vulkan; then
		local windowing=(
			$(usev X x11)
			$(usev wayland)
		)
		emesonargs+=(
			-Dvulkan-windowing=$(IFS=','; echo "${windowing[*]}")
		)
	fi

	gstreamer_multilib_src_configure
}

multilib_src_test() {
	# Tests are slower than upstream expects
	CK_DEFAULT_TIMEOUT=300 gstreamer_multilib_src_test
}

multilib_src_install() {
	gstreamer_multilib_src_install

	# Remove the VA plugin - it is provided by media-plugins/gst-plugins-va
	# to avoid file collisions. We only ship the library (libgstva-1.0.so).
	if use vaapi; then
		rm "${D}"/usr/$(get_libdir)/gstreamer-1.0/libgstva.so || die
	fi
}
