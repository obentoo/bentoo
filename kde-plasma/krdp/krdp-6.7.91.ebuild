# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: BDEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: DEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: PATCHES - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: RDEPEND - upstream 6.8 beta, not in ::gentoo yet.

ECM_EXAMPLES="true"
ECM_TEST="true"
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm flag-o-matic plasma.kde.org toolchain-funcs xdg

DESCRIPTION="Library and examples for creating an RDP server"
HOMEPAGE+=" https://quantumproductions.info/articles/2023-08/remote-desktop-using-rdp-protocol-plasma-wayland"

LICENSE="GPL-2" # TODO: CHECK
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE="systemd"

COMMON_DEPEND="
	>=dev-libs/libei-1.6.0
	>=dev-libs/qtkeychain-0.14.2:=[qt6(+)]
	>=dev-qt/qtbase-${QTMIN}:6[concurrent,dbus,gui,network,wayland]
	>=dev-qt/qtdeclarative-${QTMIN}:6
	>=kde-frameworks/kcmutils-${KFMIN}:6
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/kcrash-${KFMIN}:6
	>=kde-frameworks/kdbusaddons-${KFMIN}:6
	>=kde-frameworks/kguiaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kstatusnotifieritem-${KFMIN}:6
	>=kde-plasma/kpipewire-${KDE_CATV}:6
	>=net-misc/freerdp-3.1:3[server]
	sys-libs/pam
	x11-libs/libxkbcommon
	systemd? ( >=sys-apps/systemd-254:= )
"
DEPEND="${COMMON_DEPEND}
	dev-libs/plasma-wayland-protocols
"
RDEPEND="${COMMON_DEPEND}
	dev-libs/kirigami-addons:6
	>=kde-frameworks/kirigami-${KFMIN}:6
"
BDEPEND="
	>=kde-frameworks/kcmutils-${KFMIN}:6
	virtual/pkgconfig
"

src_configure() {
	# std::jthread and std::stop_token are implemented as experimental in libcxx
	# enable these experimental libraries on clang systems
	# https://libcxx.llvm.org/Status/Cxx20.html#note-p0660
	[[ $(tc-get-cxx-stdlib) == 'libc++' ]] && append-cxxflags -fexperimental-library

	local mycmakeargs=(
		$(cmake_use_find_package systemd Systemd)
	)

	ecm_src_configure
}
