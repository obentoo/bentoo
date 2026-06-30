# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# TODO: ECMGenerateQDoc
ECM_TEST=true
KFMIN=6.13.0
QTMIN=6.8.1
inherit ecm kde.org

DESCRIPTION="QtQuick components providing basic image editing capabilities"
HOMEPAGE="https://invent.kde.org/libraries/kquickimageeditor
https://api.kde.org/kquickimageeditor/html/index.html"

if [[ ${KDE_BUILD_TYPE} = release ]]; then
	# 0.6.2.1 is tagged upstream but not yet published on download.kde.org;
	# fetch the tagged archive from invent.kde.org instead.
	SRC_URI="https://invent.kde.org/libraries/${PN}/-/archive/v${PV}/${PN}-v${PV}.tar.gz -> ${P}.tar.gz"
	S="${WORKDIR}/${PN}-v${PV}"
	KEYWORDS="~amd64 ~arm64 ~loong ~ppc64 ~riscv ~x86"
fi

LICENSE="LGPL-2.1+"
SLOT="6"
IUSE="+opencv"

DEPEND="
	>=dev-qt/qtbase-${QTMIN}:6[gui]
	>=dev-qt/qtdeclarative-${QTMIN}:6
	>=kde-frameworks/kconfig-${KFMIN}:6
	opencv? ( media-libs/opencv:= )
"
RDEPEND="${DEPEND}
	!${CATEGORY}/${PN}:5
	>=kde-frameworks/kirigami-${KFMIN}:6
"

PATCHES=( "${FILESDIR}/${P}-opencv5.patch" )

src_configure() {
	local mycmakeargs=(
		-DWITH_OPENCV=$(usex opencv)
	)
	ecm_src_configure
}
