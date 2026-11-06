# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE=gst-plugins-bad
inherit gstreamer-meson

DESCRIPTION="OpenCV elements for GStreamer"
KEYWORDS="~amd64 ~arm64 ~x86"

RDEPEND=">=media-libs/opencv-4.1.2-r3:=[contrib,contribdnn,${MULTILIB_USEDEP}]"
DEPEND="${RDEPEND}"

# BENTOO-DIVERGENCE: PATCHES - ::gentoo solves the same problem in src_install,
# copying gst-libs/gst/opencv out of a full gst-plugins-bad build by hand. This
# patches the meson tree instead so only the opencv plugin and its helper are
# built at all. Rebased per series: the subdir lists in gst-libs/gst/ and
# meson.build move between 1.28 and 1.29, so one shared patch cannot apply to
# both -- see the header of 1.28.6's copy.
PATCHES=(
	"${FILESDIR}"/gst-plugins-bad-1.28.6-use-system-libs-opencv.patch
)

multilib_src_configure() {
	local emesonargs=(
		# We need to disable here to avoid colliding w/ gst-plugins-bad
		# on translations, because we currently do a "full" install in
		# multilib_src_install in this package. See bug #907480.
		-Dnls=disabled
	)

	gstreamer_multilib_src_configure
}

multilib_src_install() {
	DESTDIR="${D}" eninja install
}
