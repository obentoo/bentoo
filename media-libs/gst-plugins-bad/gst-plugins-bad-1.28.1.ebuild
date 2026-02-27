# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE="gst-plugins-bad"
inherit gstreamer-meson

DESCRIPTION="Less plugins for GStreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"

LICENSE="LGPL-2"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~mips ppc ppc64 ~riscv ~sparc x86"

IUSE="X bzip2 +introspection +orc udev vaapi vnc wayland"

# X11 is automagic for now, upstream #709530 - only used by librfb USE=vnc plugin
# Baseline requirement for libva is 1.6, but 1.15 gets more features
RDEPEND="
	!media-plugins/gst-transcoder

	>=media-libs/gstreamer-${PV}:${SLOT}[${MULTILIB_USEDEP},introspection?]
	>=media-libs/gst-plugins-base-${PV}:${SLOT}[${MULTILIB_USEDEP},introspection?]
	introspection? ( >=dev-libs/gobject-introspection-1.82.0-r2:= )

	bzip2? ( >=app-arch/bzip2-1.0.6-r4[${MULTILIB_USEDEP}] )
	vnc? ( X? ( x11-libs/libX11[${MULTILIB_USEDEP}] ) )
	wayland? (
		>=dev-libs/wayland-1.4.0[${MULTILIB_USEDEP}]
		>=x11-libs/libdrm-2.4.98[${MULTILIB_USEDEP}]
		>=dev-libs/wayland-protocols-1.26
	)

	orc? ( >=dev-lang/orc-0.4.33[${MULTILIB_USEDEP}] )

	vaapi? (
		>=media-plugins/gst-plugins-va-${PV}:${SLOT}[${MULTILIB_USEDEP}]
		>=media-libs/libva-1.15:=[${MULTILIB_USEDEP}]
		udev? ( dev-libs/libgudev[${MULTILIB_USEDEP}] )
	)
"
DEPEND="${RDEPEND}"
BDEPEND="
	dev-util/glib-utils
	wayland? ( dev-util/wayland-scanner )
"

DOCS=( ChangeLog NEWS README.md RELEASE )

src_prepare() {
	default
	addpredict /dev # Prevent sandbox violations bug #570624
	# GStreamer 1.28+ uses meson.options but the eclass expects meson_options.txt
	[[ -f "${S}/meson.options" && ! -f "${S}/meson_options.txt" ]] && \
		ln -s meson.options "${S}/meson_options.txt" || die
}

multilib_src_configure() {
	GST_PLUGINS_NOAUTO="bz2 hls ipcpipeline lcevcdecoder lcevcencoder librfb shm va wayland"

	local emesonargs=(
		-Dshm=enabled
		-Dipcpipeline=enabled
		-Dhls=disabled
		-Dlcevcdecoder=disabled
		-Dlcevcencoder=disabled

		$(meson_feature bzip2 bz2)
		$(meson_feature vaapi va)
		-Dudev=$(usex udev $(usex vaapi enabled disabled) disabled)
		$(meson_feature vnc librfb)
		-Dx11=$(usex X $(usex vnc enabled disabled) disabled)
		$(meson_feature wayland)
	)

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
		rm -f "${D}"/usr/$(get_libdir)/gstreamer-1.0/libgstva.so || die
	fi
}
