# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 019 ebuild, bumped to 020; python3_15 added.
# 020 changes no build option or dependency; its new brat test suite
# compares against an installed copy, so it is not wired up.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT.
PYTHON_COMPAT=( python3_{11..15} )
inherit meson python-single-r1

DESCRIPTION="USB enumeration utilities"
HOMEPAGE="
	https://www.kernel.org/pub/linux/utils/usb/usbutils/
	https://git.kernel.org/pub/scm/linux/kernel/git/gregkh/usbutils.git/
"
SRC_URI="https://www.kernel.org/pub/linux/utils/usb/${PN}/${P}.tar.xz"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="python usbreset"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

DEPEND="
	virtual/libusb:1=
	virtual/libudev:=
"
RDEPEND="
	${DEPEND}
	python? (
		${PYTHON_DEPS}
		sys-apps/hwdata
	)
"
BDEPEND="
	virtual/pkgconfig
	python? ( ${PYTHON_DEPS} )
"

pkg_setup() {
	use python && python-single-r1_pkg_setup
}

src_prepare() {
	default

	use python && python_fix_shebang lsusb.py
}

src_install() {
	meson_src_install

	if use usbreset ; then
		# https://github.com/gregkh/usbutils/issues/214
		dobin "${BUILD_DIR}"/usbreset
		doman man/usbreset.1
	fi

	if ! use python ; then
		rm -f "${ED}"/usr/bin/lsusb.py || die
	fi
}

pkg_postinst() {
	if use usbreset ; then
		ewarn "Please be warned that 'usbreset' has been built and installed, but it could"
		ewarn "damage your hardware, see upstream issue:"
		ewarn "  https://github.com/gregkh/usbutils/issues/214"
	fi
}
