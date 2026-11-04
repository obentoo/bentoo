# Copyright 2021-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..15} )
QT6_HAS_STATIC_LIBS=1
# behaves very badly when qtdeclarative is not already installed, also
# other more minor issues (installs junk, sandbox/offscreen issues)
QT6_RESTRICT_TESTS=1
inherit python-any-r1 qt6-build

DESCRIPTION="Qt Declarative (Quick 2)"

if [[ ${QT6_BUILD_TYPE} == release ]]; then
	KEYWORDS="~amd64 ~arm ~arm64 ~hppa ~loong ~ppc ~ppc64 ~riscv ~x86"
fi

IUSE="
	accessibility +jit +network opengl qmlls +sql +ssl svg vulkan
	wayland +widgets
"

RDEPEND="
	~dev-qt/qtbase-${PV}:6[accessibility=,gui,network=,opengl=,sql?,ssl?,vulkan=,wayland=,widgets=]
	qmlls? ( ~dev-qt/qtlanguageserver-${PV}:6 )
	svg? ( ~dev-qt/qtsvg-${PV}:6 )
"
DEPEND="
	${RDEPEND}
	vulkan? ( dev-util/vulkan-headers )
"
BDEPEND="
	${PYTHON_DEPS}
	~dev-qt/qtshadertools-${PV}:6
"

# BENTOO-DIVERGENCE: PATCHES - QTBUG-149607 (KDE #508377) is NOT in the 6.12.0
# tarball: the 6.12 cherry-pick 8c23f65ec488 landed after the tag, which is why
# ::gentoo's 6.12.9999 template carries no patch. ::gentoo's 6.11.2 patch does
# not apply here (qqmlpropertyvalidator.cpp); this is upstream's own pick.
# Drop on 6.12.1. The pager/plasmashell-exit patch is ::gentoo's own, taken
# from its 6.12.0-r1 so this copy is a strict superset of it.
PATCHES=(
	"${FILESDIR}"/${PN}-6.12.0-QTBUG-149607.patch
	"${FILESDIR}"/${PN}-6.12.0-pager-plasmashell-exit.patch
)

src_configure() {
	local mycmakeargs=(
		$(cmake_use_find_package qmlls Qt6LanguageServerPrivate)
		$(cmake_use_find_package sql Qt6Sql)
		$(cmake_use_find_package svg Qt6Svg)
		$(qt_feature jit qml_jit)
		$(qt_feature network qml_network)
		$(qt_feature ssl qml_ssl)
	)

	qt6-build_src_configure
}

src_install() {
	qt6-build_src_install

	if [[ ! -e ${D}${QT6_LIBDIR}/libQt6QuickControls2.so.6 ]]; then #940675
		eerror "${CATEGORY}/${PF} seems to have been improperly built and"
		eerror "install was aborted to protect the system. Possibly(?) due"
		eerror "to a rare portage ordering bug. If using portage, try:"
		eerror "    emerge -1 qtshadertools:6 qtdeclarative:6"
		eerror "If that did not resolve the issue, please provide build.log"
		eerror "on https://bugs.gentoo.org/940675"
		die "aborting due to incomplete/broken build (see above)"
	fi
}
