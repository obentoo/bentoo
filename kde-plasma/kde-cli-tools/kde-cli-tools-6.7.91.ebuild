# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: PATCHES - upstream 6.8 beta, not in ::gentoo yet.

ECM_HANDBOOK="forceoff"
ECM_TEST="false"
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm plasma.kde.org xdg

DESCRIPTION="Tools based on KDE Frameworks 6 to better interact with the system"
HOMEPAGE="https://invent.kde.org/plasma/kde-cli-tools"

LICENSE="GPL-2" # TODO: CHECK
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE="kdesu X"

# slot op: kstart Uses Qt6::GuiPrivate for qtx11extras_p.h
DEPEND="
	>=dev-qt/qtbase-${QTMIN}:6[dbus,gui,widgets]
	>=dev-qt/qtsvg-${QTMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kio-${KFMIN}:6
	>=kde-frameworks/kservice-${KFMIN}:6
	X? ( >=dev-qt/qtbase-${QTMIN}:6=[gui,X] )
"
RDEPEND="${DEPEND}
	>=${CATEGORY}/${PN}-common-${PV}
	kdesu? ( >=${CATEGORY}/kdesu-gui-${PV} )
"
BDEPEND=">=kde-frameworks/kcmutils-${KFMIN}:6"

src_prepare() {
	ecm_src_prepare
	ecm_punt_po_install
	cmake_comment_add_subdirectory keditfiletype # split package
}

src_configure() {
	local mycmakeargs=(
		-DCMAKE_DISABLE_FIND_PACKAGE_KF6Su=ON
		-DWITH_X11=$(usex X)
	)

	ecm_src_configure
}
