# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE="gst-plugins-ugly"
inherit gstreamer-meson

DESCRIPTION="Basepack of plugins for gstreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"

LICENSE="LGPL-2+" # some split plugins are LGPL but combining with a GPL library
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~mips ppc ppc64 ~riscv ~sparc x86"

RDEPEND="
	>=media-libs/gst-plugins-base-${PV}:${SLOT}[${MULTILIB_USEDEP}]
"
DEPEND="${RDEPEND}"

DOCS=( AUTHORS ChangeLog NEWS README.md RELEASE )

src_prepare() {
	default
	# GStreamer 1.28+ uses meson.options but the eclass expects meson_options.txt
	[[ -f "${S}/meson.options" && ! -f "${S}/meson_options.txt" ]] && \
		ln -s meson.options "${S}/meson_options.txt" || die
}
