# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

MY_PN=Vulkan-ValidationLayers
PYTHON_COMPAT=( python3_{11..14} )
inherit cmake-multilib python-any-r1

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/KhronosGroup/${MY_PN}.git"
	EGIT_SUBMODULES=()
	inherit git-r3
else
	EGIT_COMMIT="ad4ed518c3c9783b9c9ff912c205c987b17d7bf4"
	SRC_URI="https://github.com/KhronosGroup/${MY_PN}/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
	S="${WORKDIR}"/${MY_PN}-${EGIT_COMMIT}
fi

DESCRIPTION="Vulkan Validation Layers"
HOMEPAGE="https://github.com/KhronosGroup/Vulkan-ValidationLayers"

LICENSE="Apache-2.0"
SLOT="0"
IUSE="wayland test X"
RESTRICT="!test? ( test ) test"

# BENTOO-DIVERGENCE: DEPEND - ::gentoo pins the SDK in lockstep (~pkg-${PV});
# bentoo ships snapshots that bump on independent dates, so an exact pin can
# never be satisfied. Floors on the companion snapshots keep the coupling the
# pins exist to enforce. Raise them on every bump of any of the five.
RDEPEND=">=dev-util/spirv-tools-1.4.357.0_p20260828-r1[${MULTILIB_USEDEP}]"
DEPEND="${RDEPEND}
	${PYTHON_DEPS}
	>=dev-util/glslang-1.4.357.0_p20260813:=[${MULTILIB_USEDEP}]
	>=dev-util/spirv-headers-1.4.357.0_p20260826-r1
	>=dev-util/vulkan-headers-1.4.360_p20260814
	>=dev-util/vulkan-utility-libraries-1.4.360:=[${MULTILIB_USEDEP}]
	wayland? ( dev-libs/wayland:=[${MULTILIB_USEDEP}] )
	X? (
		x11-libs/libX11:=[${MULTILIB_USEDEP}]
		x11-libs/libXrandr:=[${MULTILIB_USEDEP}]
	)
"

QA_SONAME="/usr/lib[^/]*/libVkLayer_khronos_validation.so"

PATCHES=(
	"${FILESDIR}"/${PN}-descriptor-hashing-32bit-align.patch
)

multilib_src_configure() {
	local mycmakeargs=(
		-DCMAKE_C_FLAGS="${CFLAGS} -DNDEBUG"
		-DCMAKE_CXX_FLAGS="${CXXFLAGS} -DNDEBUG"
		-DCMAKE_SKIP_RPATH=ON
		-DBUILD_WERROR=OFF
		-DBUILD_WSI_WAYLAND_SUPPORT=$(usex wayland)
		-DBUILD_WSI_XCB_SUPPORT=$(usex X)
		-DBUILD_WSI_XLIB_SUPPORT=$(usex X)
		-DBUILD_TESTS=$(usex test)
		-DVULKAN_HEADERS_INSTALL_DIR="${ESYSROOT}/usr"
		-DFETCHCONTENT_FULLY_DISCONNECTED=ON
		-DUPDATE_DEPS=OFF
	)
	cmake_src_configure
}

multilib_src_install_all() {
	find "${ED}" -type f -name \*.a -delete || die
}
