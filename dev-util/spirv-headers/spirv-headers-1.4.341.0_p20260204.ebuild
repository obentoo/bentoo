# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN=SPIRV-Headers
inherit cmake

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/KhronosGroup/${MY_PN}.git"
	inherit git-r3
else
	EGIT_COMMIT="f31ca173eff866369e54d35e53375fadbabd58f4"
	SRC_URI="https://github.com/KhronosGroup/${MY_PN}/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
	S="${WORKDIR}"/${MY_PN}-${EGIT_COMMIT}
fi

DESCRIPTION="Machine-readable files for the SPIR-V Registry"
HOMEPAGE="https://registry.khronos.org/SPIR-V/ https://github.com/KhronosGroup/SPIRV-Headers"

LICENSE="MIT"
SLOT="0"

src_configure() {
	local mycmakeargs=(
		-DSPIRV_HEADERS_ENABLE_TESTS=OFF
		-DSPIRV_HEADERS_ENABLE_INSTALL=ON
	)
	cmake_src_configure
}
