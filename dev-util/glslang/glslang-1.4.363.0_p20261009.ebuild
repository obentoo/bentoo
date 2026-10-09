# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )
inherit cmake-multilib python-any-r1

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/KhronosGroup/${PN}.git"
	inherit git-r3
else
	GIT_COMMIT="37b5bd7264c2c4acfa6f11826c29a16ab6a2a699"
	SRC_URI="https://github.com/KhronosGroup/${PN}/archive/${GIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
	S="${WORKDIR}/${PN}-${GIT_COMMIT}"
fi

DESCRIPTION="Khronos reference front-end for GLSL and ESSL, and sample SPIR-V generator"
HOMEPAGE="https://www.khronos.org/opengles/sdk/tools/Reference-Compiler/ https://github.com/KhronosGroup/glslang"

LICENSE="BSD"
# BENTOO-DIVERGENCE: SLOT - ::gentoo tracks the released tag and carries 0/16.4;
# this snapshot builds libglslang.so.16.5.0, so the subslot follows the library
# the package actually installs. It had been stale at 0/16.1 since the ebuild
# was copied over from glslang-1.4.335.0. Bump it whenever the built soname
# minor changes -- glslang breaks C++ ABI between minors.
SLOT="0/16.5"

# BENTOO-DIVERGENCE: DEPEND - ::gentoo pins the SDK in lockstep (~pkg-${PV});
# bentoo ships snapshots that bump on independent dates, so an exact pin can
# never be satisfied. A floor on the companion snapshot keeps the coupling the
# pin exists to enforce. Raise it on every spirv-tools bump.
BDEPEND="${PYTHON_DEPS}
	>=dev-util/spirv-tools-1.4.357.0_p20260813[${MULTILIB_USEDEP}]
"

DEPEND=">=dev-util/spirv-tools-1.4.357.0_p20260813[${MULTILIB_USEDEP}]"
RDEPEND="${DEPEND}"

# BENTOO-DIVERGENCE: PATCHES - there is no PATCHES array here, while ::gentoo's
# 1.4.357.0 applies ${PV}-Fix-format-specifier-for-64-bit-index-in-error-messa
# .patch. That patch is a cherry-pick of upstream b44e6091 (2026-09-14), which
# makes the "index out of range" messages print the int64_t index with %lld
# instead of %d -- on 32-bit ARM and PowerPC the %d read variadic padding and
# printed garbage.
#
# This snapshot is 31b9aacf, cut 2026-09-16, so it is DOWNSTREAM of that commit
# and already carries the fix. Verified in the tarball rather than inferred
# from dates: glslang/MachineIndependent/ParseHelper.cpp has the %lld form with
# the (long long) cast at all three call sites.
#
# Adding the patch would not be harmless. eapply runs `patch -f`, so an already
# applied hunk does not get skipped -- it fails, or worse, applies in reverse
# and reintroduces the bug. Re-check this on every snapshot bump ONLY if the
# snapshot ever moves backwards; a later commit can only keep the fix.

multilib_src_configure() {
	local mycmakeargs=(
		-DENABLE_PCH=OFF
		-DALLOW_EXTERNAL_SPIRV_TOOLS=ON
	)
	cmake_src_configure
}

multilib_src_test() {
	local CMAKE_SKIP_TESTS=(
		# bug #977176 (https://github.com/KhronosGroup/glslang/issues/4180)
		# We keyword ~arm, so we need the skip that makes ~arm testable --
		# without it USE=test fails on the one arch it was added for.
		$(usev arm 'glslang-testsuite')
	)
	cmake_src_test
}
