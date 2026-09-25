# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: DEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: IUSE - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: PATCHES - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: RDEPEND - upstream 6.8 beta, not in ::gentoo yet.

ECM_TEST="forceoptional"
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm plasma.kde.org xdg

DESCRIPTION="KDE Plasma screen management"
HOMEPAGE="https://invent.kde.org/plasma/kscreen"

LICENSE="GPL-2" # TODO: CHECK
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE=""

# slot op: Uses Qt6GuiPrivate and Qt6WaylandClientPrivate
COMMON_DEPEND="
	>=dev-qt/qtbase-${QTMIN}:6=[dbus,gui,wayland,widgets]
	>=dev-qt/qtdeclarative-${QTMIN}:6[widgets]
	>=kde-frameworks/kcmutils-${KFMIN}:6
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/kcrash-${KFMIN}:6
	>=kde-frameworks/kdbusaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/ksvg-${KFMIN}:6
	>=kde-frameworks/kwindowsystem-${KFMIN}:6
	>=kde-frameworks/kxmlgui-${KFMIN}:6
	>=kde-plasma/layer-shell-qt-${KDE_CATV}:6
	>=kde-plasma/libkscreen-${KDE_CATV}:6=
	>=kde-plasma/libplasma-${KDE_CATV}:6=
"
RDEPEND="${COMMON_DEPEND}
	!ppc64? ( >=kde-frameworks/kimageformats-${KFMIN}:6[avif] )
	>=kde-frameworks/kitemmodels-${KFMIN}:6
	>=kde-plasma/kglobalacceld-${KDE_CATV}:6
	>=kde-plasma/plasma5support-${KDE_CATV}:6
"
DEPEND="${COMMON_DEPEND}
	>=dev-libs/wayland-protocols-1.41
"
BDEPEND="
	>=dev-qt/qtbase-${QTMIN}:6[wayland]
	dev-util/wayland-scanner
	>=kde-frameworks/kcmutils-${KFMIN}:6
	virtual/pkgconfig
"

src_prepare() {
	ecm_src_prepare
	use ppc64 && cmake_comment_add_subdirectory hdrcalibrator # avif masked on big-endian
}
