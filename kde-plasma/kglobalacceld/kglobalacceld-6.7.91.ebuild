# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: DEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: IUSE - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: RDEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: REQUIRED_USE - upstream 6.8 beta, not in ::gentoo yet.

ECM_TEST="true"
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm plasma.kde.org

DESCRIPTION="Daemon providing Global Keyboard Shortcut (Accelerator) functionality"

LICENSE="LGPL-2+"
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE=""

RESTRICT="test" # requires installed instance

DEPEND="
	>=dev-qt/qtbase-${QTMIN}:6[dbus,gui]
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/kio-${KFMIN}:6
	>=kde-frameworks/kjobwidgets-${KFMIN}:6
	>=kde-frameworks/knotifications-${KFMIN}:6
	>=kde-frameworks/kservice-${KFMIN}:6
"
RDEPEND="${DEPEND}
	!<kde-frameworks/kglobalaccel-5.116.0-r2:5[-kf6compat(-)]
"
BDEPEND=">=dev-qt/qttools-${QTMIN}:6[linguist]"

# src_test() {
# 	XDG_CURRENT_DESKTOP="KDE" ecm_src_test # bug 789342
# }
