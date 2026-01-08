# Copyright 2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake multilib-minimal

DESCRIPTION="MPEG-5 LCEVC Decoder SDK by V-Nova"
HOMEPAGE="https://github.com/v-novaltd/LCEVCdec"
SRC_URI="https://github.com/v-novaltd/LCEVCdec/archive/refs/tags/${PV}.tar.gz"

LICENSE="V-Nova-LCEVC"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE=""

# This package uses a custom non-free license
RESTRICT="mirror"

DEPEND=""
RDEPEND="${DEPEND}"
BDEPEND="virtual/pkgconfig"

S="${WORKDIR}/LCEVCdec-${PV}"

src_prepare() {
	sed -i '/static bool detectAVX2/,/^}/ {
    /loadCPUInfo(cpuInfo, 0);/{
        N
        s/loadCPUInfo(cpuInfo, 0);\n    if (nids < 7) {/loadCPUInfo(cpuInfo, 0);\n    if (cpuInfo[0] < 1) {\n        return false;\n    }\n    loadCPUInfo(cpuInfo, 1);\n    if (cpuInfo[0] < 7) {/
    }
}' "${S}"/src/common/src/acceleration.c || die "sed failed"
	cmake_src_prepare
	default
}

multilib_src_configure() {
	cmake_src_configure
}

multilib_src_compile() {
	cmake_src_compile
}

multilib_src_install() {
	cmake_src_install
}
