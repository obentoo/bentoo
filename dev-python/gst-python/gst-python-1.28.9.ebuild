# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{12..15} )

inherit meson python-r1 verify-sig xdg-utils

DESCRIPTION="A Python Interface to GStreamer"
HOMEPAGE="https://gstreamer.freedesktop.org/"
SRC_URI="https://gstreamer.freedesktop.org/src/${PN}/${P}.tar.xz"
SRC_URI+=" verify-sig? ( https://gstreamer.freedesktop.org/src/${PN}/${P}.tar.xz.asc )"

LICENSE="LGPL-2+"
SLOT="1.0"
KEYWORDS="~alpha amd64 ~arm ~arm64 ~hppa ~loong ~ppc ppc64 ~riscv ~sparc x86"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="${PYTHON_DEPS}
	>=media-libs/gstreamer-${PV}:1.0[introspection]
	>=media-libs/gst-plugins-bad-${PV}:1.0[introspection]
	>=media-libs/gst-plugins-base-${PV}:1.0[introspection]
	>=dev-python/pygobject-3.8:3[${PYTHON_USEDEP}]
"
DEPEND="${RDEPEND}"
BDEPEND="
	virtual/pkgconfig
"

BDEPEND+=" verify-sig? ( sec-keys/openpgp-keys-tpm )"
VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/tpm.asc

# BENTOO-DIVERGENCE: PATCHES - one patch where ::gentoo has two. Their
# pygobject-3.52 patch is a backport onto 1.26.11 and reverse-applies cleanly
# against 1.28.6, so the plugins_install_dir work it adds is already upstream
# here. Their skip-test one is NOT upstream and IS needed - it is the patch
# above.
# Taken from ::gentoo 2026-09-07 and renamed version-agnostic, because the
# autoupdate applier never renames anything under files/. Upstream has not
# applied it: testsuite/test_gst_init.py still carries both tests unskipped in
# 1.28.6 and 1.29.2, and neither side declares IUSE=test or RESTRICT, so
# FEATURES=test runs them and they fail against >=dev-python/pygobject-3.54.
# Verified to apply -p1 to both tarballs before adding.
PATCHES=(
	"${FILESDIR}"/${PN}-skip-pygobject-broken-tests.patch
)

src_prepare() {
	default

	# Avoid building & testing plugin - it must NOT be multi-python as gst-inspect will map in all libpython.so versions
	# and crash or behave mysteriously.
	# Python plugin support is of limited use (GIL gets in the way). If it's ever requested or needed, it should be a
	# separate python-single-r1 media-plugins/gst-plugins-python package that only builds the plugin directory.
	sed -e '/subdir.*plugin/d' -i meson.build || die
	sed -e '/test_plugin.py/d' -i testsuite/meson.build || die

	xdg_environment_reset
}

src_configure() {
	configuring() {
		meson_src_configure \
			-Dpython="${EPYTHON}"
	}
	python_foreach_impl configuring
}

src_compile() {
	python_foreach_impl meson_src_compile
}

src_test() {
	python_foreach_impl meson_src_test
}

src_install() {
	installing() {
		meson_src_install
		python_optimize
	}
	python_foreach_impl installing
}
