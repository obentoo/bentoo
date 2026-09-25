# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: DEFINED_PHASES - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: DEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: INHERIT - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: RDEPEND - upstream 6.8 beta, not in ::gentoo yet.

ECM_HANDBOOK="forceoptional"
KDE_ORG_CATEGORY="plasma"
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm plasma.kde.org xdg

DESCRIPTION="Backup scheduler for the Plasma desktop"
HOMEPAGE="https://apps.kde.org/kup/"

LICENSE="GPL-2+"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE=""

DEPEND="
	dev-libs/libgit2:=
	>=dev-qt/qtbase-${QTMIN}:6[dbus,gui,network,widgets]
	>=kde-frameworks/kcmutils-${KFMIN}:6
	>=kde-frameworks/kcompletion-${KFMIN}:6
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kconfigwidgets-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/kcrash-${KFMIN}:6
	>=kde-frameworks/kdbusaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kidletime-${KFMIN}:6
	>=kde-frameworks/kio-${KFMIN}:6
	>=kde-frameworks/kjobwidgets-${KFMIN}:6
	>=kde-frameworks/knotifications-${KFMIN}:6
	>=kde-frameworks/kwidgetsaddons-${KFMIN}:6
	>=kde-frameworks/kwindowsystem-${KFMIN}:6
	>=kde-frameworks/kxmlgui-${KFMIN}:6
	>=kde-frameworks/solid-${KFMIN}:6
	>=kde-plasma/libplasma-${KDE_CATV}:6=
"
RDEPEND="${DEPEND}
	>=dev-qt/qtdeclarative-${QTMIN}:6
	>=dev-qt/qtsvg-${QTMIN}:6
	net-misc/rsync
"
