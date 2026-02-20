# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE=gst-plugins-bad

inherit gstreamer-meson

DESCRIPTION="NVIDIA GPU codec (NVENC/NVDEC) plugin for GStreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"
KEYWORDS="~amd64"

# nv-codec-headers provides the NVENC/NVDEC API headers needed at build time.
# At runtime, NVIDIA drivers provide libcuda.so.1, libnvcuvid.so and
# libnvidia-encode.so via dlopen (no link-time CUDA dependency).
RDEPEND="
	>=media-libs/gst-plugins-bad-${PV}:${SLOT}[${MULTILIB_USEDEP}]
	x11-drivers/nvidia-drivers[${MULTILIB_USEDEP}]
"
DEPEND="${RDEPEND}
	>=media-libs/nv-codec-headers-11.1.5.0
"
