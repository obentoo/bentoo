# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
GST_ORG_MODULE="gst-plugins-ugly"
inherit gstreamer-meson verify-sig

DESCRIPTION="Basepack of plugins for gstreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"
SRC_URI+=" verify-sig? ( https://gstreamer.freedesktop.org/src/${GST_ORG_MODULE}/${GST_ORG_MODULE}-${PV}.tar.xz.asc )"

LICENSE="LGPL-2+" # some split plugins are LGPL but combining with a GPL library
KEYWORDS="~alpha amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ppc64 ~riscv ~sparc x86"

RDEPEND="
	>=media-libs/gst-plugins-base-${PV}:${SLOT}[${MULTILIB_USEDEP}]
"
DEPEND="${RDEPEND}"

DOCS=( README.md )

BDEPEND+=" verify-sig? ( sec-keys/openpgp-keys-tpm )"
VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/tpm.asc
