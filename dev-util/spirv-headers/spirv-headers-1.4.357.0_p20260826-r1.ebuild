# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN=SPIRV-Headers
inherit cmake

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/KhronosGroup/${MY_PN}.git"
	inherit git-r3
else
	# -r1: upstream landed two commits on 2026-08-26 and a _p<YYYYMMDD> snapshot
	# cannot tell them apart. This is the second, 496543121ce6
	# (SPV_QCOM_subgroup_size, #626); the first, 2209d5325ba5, is what -r0
	# shipped. Vulkan-ValidationLayers f95e5bbc names 496543121ce6 in
	# known_good.json, and its pre-generated spirv_grammar_helper.cpp fails to
	# compile without it: spv::ExecutionModeSubgroupSize{Half,Full}QCOM do not
	# exist in the older header.
	# The rename target is ${PF}, not ${P}: PV carries no revision, so both
	# revisions would fetch different content into one distfile name.
	EGIT_COMMIT="496543121ce6419f23d6fa5d7194ba66c36212d2"
	SRC_URI="https://github.com/KhronosGroup/${MY_PN}/archive/${EGIT_COMMIT}.tar.gz -> ${PF}.tar.gz"
	KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"
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
