# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 2.19.0 ebuild, bumped to 2.20.0; python3_15 added.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT.
PYTHON_COMPAT=( python3_{12..15} )
inherit meson python-any-r1 udev

DESCRIPTION="Library for identifying Wacom tablets and their model-specific features"
HOMEPAGE="https://github.com/linuxwacom/libwacom"
SRC_URI="https://github.com/linuxwacom/${PN}/releases/download/${P}/${P}.tar.xz"

LICENSE="MIT"
SLOT="0/9" # libwacom SONAME
KEYWORDS="~amd64"
IUSE="doc test"
RESTRICT="!test? ( test )"

RDEPEND="
	>=dev-libs/glib-2.68:2
	dev-libs/libevdev
	dev-libs/libgudev:=
"
DEPEND="${RDEPEND}"
BDEPEND="
	${PYTHON_DEPS}
	virtual/pkgconfig
	doc? ( app-text/doxygen )
	test? (
		$(python_gen_any_dep '
			dev-python/libevdev[${PYTHON_USEDEP}]
			dev-python/pyudev[${PYTHON_USEDEP}]
			dev-python/pytest[${PYTHON_USEDEP}]
		')
	)
"

python_check_deps() {
	use test || return 0
	python_has_version \
		"dev-python/libevdev[${PYTHON_USEDEP}]" \
		"dev-python/pyudev[${PYTHON_USEDEP}]" \
		"dev-python/pytest[${PYTHON_USEDEP}]"
}

src_configure() {
	local emesonargs=(
		$(meson_feature doc documentation)
		$(meson_feature test tests)
		-Dudev-dir=$(get_udevdir)
	)
	meson_src_configure
}

pkg_postinst() {
	udev_reload
}

pkg_postrm() {
	udev_reload
}
