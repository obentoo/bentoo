# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
PYTHON_COMPAT=( python3_{12..14} )

inherit meson python-r1 verify-sig

DESCRIPTION="SDK for making video editors and more"
HOMEPAGE="http://wiki.pitivi.org/wiki/GES"
SRC_URI="https://gstreamer.freedesktop.org/src/${PN}/${P/gstreamer/gst}.tar.xz"
SRC_URI+=" verify-sig? ( https://gstreamer.freedesktop.org/src/${PN}/${P/gstreamer/gst}.tar.xz.asc )"
S="${WORKDIR}"/${P/gstreamer/gst}

LICENSE="LGPL-2+"
SLOT="1.0"
KEYWORDS="amd64 ~arm64 x86"

IUSE="+introspection test"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"
# Some tests are failing
RESTRICT="test"

RDEPEND="
	${PYTHON_DEPS}
	dev-python/pygobject[${PYTHON_USEDEP}]
	>=dev-libs/glib-2.40.0:2
	dev-libs/libxml2:2=
	>=media-libs/gstreamer-${PV}:1.0[introspection?]
	>=media-libs/gst-plugins-base-${PV}:1.0[introspection?]
	>=media-libs/gst-plugins-bad-${PV}:1.0[introspection?]
	introspection? ( >=dev-libs/gobject-introspection-1.82.0-r2:= )
"
DEPEND="${RDEPEND}"
BDEPEND="virtual/pkgconfig"

BDEPEND+=" verify-sig? ( sec-keys/openpgp-keys-tpm )"
VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/tpm.asc

src_configure() {
	python_setup

	local emesonargs=(
		-Ddoc=disabled # hotdoc not packaged
		$(meson_feature introspection)
		$(meson_feature test tests)
		-Dbash-completion=disabled
		-Dxptv=disabled
		-Dpython=enabled
		-Dvalidate=disabled
		-Dexamples=disabled
	)
	meson_src_configure
}

src_install() {
	meson_src_install
	python_moduleinto gi.overrides
	python_foreach_impl python_domodule bindings/python/gi/overrides/GES.py
}
