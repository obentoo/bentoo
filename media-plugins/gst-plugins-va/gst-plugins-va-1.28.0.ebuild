# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE=gst-plugins-bad

inherit gstreamer-meson

DESCRIPTION="VA-API video acceleration plugin for GStreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"

LICENSE="LGPL-2.1+"
SLOT="1.0"
KEYWORDS="amd64 ~arm64 ~riscv x86"

RDEPEND="
	!!media-plugins/gst-plugins-vaapi
	>=media-libs/gst-plugins-bad-${PV}:${SLOT}[${MULTILIB_USEDEP}]
	>=media-libs/libva-1.15.0:=[${MULTILIB_USEDEP}]
"
DEPEND="${RDEPEND}"
