# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN=SPIRV-Tools
PYTHON_COMPAT=( python3_{11..14} )
PYTHON_REQ_USE="xml(+)"
inherit cmake-multilib python-any-r1

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/KhronosGroup/${MY_PN}.git"
	inherit git-r3
else
	EGIT_COMMIT="fd9bc85c546219b61b04556695c17f4ac3a4192a"
	SRC_URI="https://github.com/KhronosGroup/${MY_PN}/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"
	S="${WORKDIR}"/${MY_PN}-${EGIT_COMMIT}
fi

DESCRIPTION="Provides an API and commands for processing SPIR-V modules"
HOMEPAGE="https://github.com/KhronosGroup/SPIRV-Tools"

LICENSE="Apache-2.0"
SLOT="0"
IUSE="test"
RESTRICT="!test? ( test )"

# BENTOO-DIVERGENCE: DEPEND - ::gentoo pins the SDK in lockstep (~pkg-${PV});
# bentoo ships snapshots that bump on independent dates, so an exact pin can
# never be satisfied. The floor keeps the coupling the pin exists to enforce:
# core_tables_body.inc is generated from grammar files that only newer
# spirv-headers ship (obentoo/bentoo#37). Raise it on every spirv-headers bump.
#
# Why a revbump is sometimes needed, even with no source change:
# core_tables_body.inc is generated at build time from the grammar the header
# package installs, so a spirv-headers bump silently leaves an already-merged
# spirv-tools generating tables for the OLD grammar. Raising the floor alone
# does not recompile anything; only a revision makes portage do it. The
# 1.4.357.0_p20260826-r1 case (picking up SPV_QCOM_subgroup_size) was the
# precedent. Corrected 2026-09-04: this paragraph used to describe that -r1 in
# the present tense. It no longer exists and EGIT_COMMIT has moved since --
# what survives is the mechanism, which applies to every future header bump.
DEPEND=">=dev-util/spirv-headers-1.4.357.0_p20260826-r1"
# RDEPEND=""
BDEPEND="${PYTHON_DEPS}"

multilib_src_configure() {
	local mycmakeargs=(
		-DSPIRV-Headers_SOURCE_DIR="${ESYSROOT}"/usr/
		-DSPIRV_WERROR=OFF
		-DSPIRV_SKIP_TESTS=$(usex !test)
		-DSPIRV_TOOLS_BUILD_STATIC=OFF
		-DCMAKE_C_FLAGS="${CFLAGS} -DNDEBUG"
		-DCMAKE_CXX_FLAGS="${CXXFLAGS} -DNDEBUG"
	)

	cmake_src_configure
}

src_test() {
	CMAKE_SKIP_TESTS=(
		# Not relevant for us downstream
		spirv-tools-copyrights
		# Tests fail upon finding symbols that do not match a regular expression
		# in the generated library. Easily hit with non-standard compiler flags
		spirv-tools-symbol-exports.*
	)

	multilib-minimal_src_test
}
