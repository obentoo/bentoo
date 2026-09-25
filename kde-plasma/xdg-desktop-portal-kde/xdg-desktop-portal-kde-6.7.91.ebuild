# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: DEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: RDEPEND - upstream 6.8 beta, not in ::gentoo yet.

ECM_TEST="forceoptional"
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm plasma.kde.org xdg

DESCRIPTION="Backend implementation for xdg-desktop-portal that is using Qt/KDE Frameworks"

LICENSE="LGPL-2+"
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE=""

# dev-qt/qtbase:= slot op: Uses Qt::GuiPrivate for qtx11extras_p.h
# dev-qt/qtbase:=[cups]: includes specifically the cups private header
# dev-qt/qtgui: QtXkbCommonSupport is provided by either IUSE libinput or X
COMMON_DEPEND="
	>=dev-libs/wayland-1.15
	>=dev-qt/qtbase-${QTMIN}:6=[cups,dbus,gui,wayland,widgets]
	>=dev-qt/qtdeclarative-${QTMIN}:6
	|| (
		>=dev-qt/qtbase-${QTMIN}:6[libinput]
		>=dev-qt/qtbase-${QTMIN}:6[X]
	)
	>=kde-frameworks/kcoreaddons-${KFMIN}:6[dbus]
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kcrash-${KFMIN}:6
	>=kde-frameworks/kglobalaccel-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kiconthemes-${KFMIN}:6
	>=kde-frameworks/kio-${KFMIN}:6
	>=kde-frameworks/kirigami-${KFMIN}:6
	>=kde-frameworks/knotifications-${KFMIN}:6
	>=kde-frameworks/kservice-${KFMIN}:6
	>=kde-frameworks/kstatusnotifieritem-${KFMIN}:6
	>=kde-frameworks/kwidgetsaddons-${KFMIN}:6
	>=kde-frameworks/kwindowsystem-${KFMIN}:6
	>=kde-plasma/kpipewire-${KDE_CATV}:6
	>=kde-plasma/kwayland-${KDE_CATV}:6
	media-video/pipewire:=
	x11-libs/libxkbcommon
"
DEPEND="${COMMON_DEPEND}
	>=dev-libs/plasma-wayland-protocols-1.22.0
	>=dev-libs/wayland-protocols-1.25
	>=dev-qt/qtbase-${QTMIN}:6[concurrent]
"
RDEPEND="${COMMON_DEPEND}
	kde-misc/kio-fuse:6
	sys-apps/xdg-desktop-portal
"
BDEPEND="
	>=dev-qt/qtbase-${QTMIN}:6[wayland]
	virtual/pkgconfig
"

CMAKE_SKIP_TESTS=(
	# bugs: 926483, wants dbus/X11
	colorschemetest
)
