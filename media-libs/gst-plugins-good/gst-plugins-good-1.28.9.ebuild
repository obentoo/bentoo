# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE="gst-plugins-good"

# BENTOO-DIVERGENCE: INHERIT - no virtualx in this ebuild's inherit line, where
# ::gentoo lists it. Cosmetic, and checked rather than assumed: gstreamer-meson
# .eclass does "inherit virtualx" itself, in the branch taken by a top-level
# module (not a split plugin), on both sides. virtualx appears in _eclasses_ of
# both md5-cache entries, so the same eclass is loaded either way - ::gentoo
# simply restates in the ebuild what its eclass already did.
# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo carries four GStreamer security patches
# (SA-2026-0016, -0018, -0021, -0022). Those are
# backports onto THEIR 1.26.11; upstream shipped the same fixes in the series
# this ebuild tracks. Verified 2026-09-07 rather than assumed: -0018, -0021 and -0022 reverse-apply
# cleanly against the 1.28.6 tarball, and -0016's guard is present verbatim -
# qtdemux.c line 12325 already refuses a cmpd component_count above 16.
inherit gstreamer-meson verify-sig

DESCRIPTION="Basepack of plugins for GStreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"
SRC_URI+=" verify-sig? ( https://gstreamer.freedesktop.org/src/${GST_ORG_MODULE}/${GST_ORG_MODULE}-${PV}.tar.xz.asc )"

LICENSE="LGPL-2.1+"
KEYWORDS="~alpha amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ppc64 ~riscv ~sparc x86"
IUSE="+orc"

# Old media-libs/gst-plugins-ugly blocker for xingmux moving from ugly->good
RDEPEND="
	!<media-libs/gst-plugins-ugly-1.22.3
	>=media-libs/gst-plugins-base-${PV}:${SLOT}[${MULTILIB_USEDEP}]
	>=app-arch/bzip2-1.0.6-r4[${MULTILIB_USEDEP}]
	>=virtual/zlib-1.2.8-r1:=[${MULTILIB_USEDEP}]
	orc? ( >=dev-lang/orc-0.4.33[${MULTILIB_USEDEP}] )
"
DEPEND="${RDEPEND}"

DOCS=( README.md )

BDEPEND+=" verify-sig? ( sec-keys/openpgp-keys-tpm )"
VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/tpm.asc

multilib_src_configure() {
	# gst/matroska can use bzip2
	GST_PLUGINS_NOAUTO="bz2"

	local emesonargs=(
		-Dbz2=enabled
	)

	gstreamer_multilib_src_configure
}
