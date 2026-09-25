# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: DEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: RDEPEND - upstream 6.8 beta, not in ::gentoo yet.

ECM_TEST="true"
PYTHON_COMPAT=( python3_{12..15} )
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm plasma.kde.org python-single-r1 xdg

DESCRIPTION="Plasma crash handler, gives the user feedback if a program crashed"

LICENSE="GPL-2" # TODO: CHECK
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

COMMON_DEPEND="${PYTHON_DEPS}
	>=dev-qt/qtbase-${QTMIN}:6[dbus,gui,network,widgets]
	>=dev-qt/qtdeclarative-${QTMIN}:6
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/kcrash-${KFMIN}:6
	>=kde-frameworks/kdbusaddons-${KFMIN}:6
	>=kde-frameworks/kguiaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kidletime-${KFMIN}:6
	>=kde-frameworks/kio-${KFMIN}:6
	>=kde-frameworks/kjobwidgets-${KFMIN}:6
	>=kde-frameworks/knotifications-${KFMIN}:6
	>=kde-frameworks/kservice-${KFMIN}:6
	>=kde-frameworks/kstatusnotifieritem-${KFMIN}:6
	>=kde-frameworks/kwallet-${KFMIN}:6
	>=kde-frameworks/kwidgetsaddons-${KFMIN}:6
	>=kde-frameworks/kwindowsystem-${KFMIN}:6
	>=kde-frameworks/syntax-highlighting-${KFMIN}:6
	>=sys-apps/systemd-255:=
	>=sys-auth/polkit-qt-0.175.0[qt6(+)]
"
DEPEND="${COMMON_DEPEND}
	>=dev-qt/qtbase-${QTMIN}:6[concurrent]
	test? ( >=dev-qt/qtbase-${QTMIN}:6[network] )
"
RDEPEND="${COMMON_DEPEND}
	|| (
		dev-libs/elfutils[utils]
		>=dev-debug/gdb-18
	)
	>=kde-frameworks/kirigami-${KFMIN}:6
	>=kde-frameworks/kitemmodels-${KFMIN}:6
	$(python_gen_cond_dep '
		dev-python/psutil[${PYTHON_USEDEP}]
	')
	|| (
		>=dev-debug/gdb-12
		llvm-core/lldb
	)
"

src_configure() {
	local mycmakeargs=(
		-DWITH_PYTHON_VENDORING=OFF
	)
	ecm_src_configure
}

src_test() {
	# needs network access, bug #698510
	local myctestargs=(
		-E "(connectiontest)"
	)
	ecm_src_test
}
