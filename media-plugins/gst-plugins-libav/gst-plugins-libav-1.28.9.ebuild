# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# BENTOO-DIVERGENCE: INHERIT - no virtualx in this ebuild's inherit line, where
# ::gentoo lists it. Cosmetic, and checked rather than assumed: gstreamer-meson
# .eclass does "inherit virtualx" itself, in the branch taken by a top-level
# module (not a split plugin), on both sides. virtualx appears in _eclasses_ of
# both md5-cache entries, so the same eclass is loaded either way - ::gentoo
# simply restates in the ebuild what its eclass already did.
# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo carries an ffmpeg9 patch. Those are
# backports onto THEIR 1.26.11; upstream shipped the same fixes in the series
# this ebuild tracks. Verified 2026-09-07 rather than assumed: it reverse-applies cleanly against the
# 1.28.6 tarball.
inherit gstreamer-meson

MY_PN="gst-libav"
MY_PV="$(ver_cut 1-3)"
MY_P="${MY_PN}-${MY_PV}"

DESCRIPTION="FFmpeg based gstreamer plugin"
HOMEPAGE="https://gstreamer.freedesktop.org/modules/gst-libav.html"
SRC_URI="https://gstreamer.freedesktop.org/src/${MY_PN}/${MY_P}.tar.xz"
S="${WORKDIR}/${MY_P}"

LICENSE="LGPL-2+"
SLOT="1.0"
KEYWORDS="~alpha amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ppc64 ~riscv x86"

# 1.24.11 unconditionally used new audio channel layouts added in ffmpeg-4.4;
# 1.24.12 will build time check first. As we don't have older in tree anymore, just dep on it.
RDEPEND="
	>=dev-libs/glib-2.40.0:2[${MULTILIB_USEDEP}]
	>=media-libs/gstreamer-${MY_PV}:1.0[${MULTILIB_USEDEP}]
	>=media-libs/gst-plugins-base-${MY_PV}:1.0[${MULTILIB_USEDEP}]
	>=media-video/ffmpeg-4.4:0=[${MULTILIB_USEDEP}]
"
DEPEND="${RDEPEND}"
BDEPEND=""
