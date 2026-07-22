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
<<<<<<< HEAD
	EGIT_COMMIT="aaeec0b93f76a0a134141c7e0a88588b93b7abce"
=======
	EGIT_COMMIT="84e4e10cbe6772908f5d5b84ce1771794cefb738"
>>>>>>> 4eb9e849 (add(app-editors/{cursor-3.12.17, devin-desktop-bin-3.5.17, kiro-1.0.198, trilium-0.104.0, vim-9.2.0829, vim-core-9.2.0829, zed-1.13.0_pre20260722}, app-emulation/{crossover-bin-26.3.0, d7vk-2.0}, app-misc/claude-desktop-bin-1.24012.1, app-portage/bentoolkit-0.14.0, dev-games/godot-4.8_alpha2, dev-lang/flutter-3.44.7, dev-libs/sentry-native-0.15.4, dev-python/uv-bin-0.11.31, dev-ruby/erb-6.0.6, dev-util/codex{,-bin}-0.145.0, dev-vcs/gitkraken-12.3.1, media-libs/{mesa-26.2.0_pre20260722, vulkan-layers-1.4.352_p20260721, vulkan-loader-1.4.354_p20260720}, net-misc/{modemmanager-1.25.1_p20260721, postman-bin-12.20.1}, sci-ml/llama-cpp-0_pre10085, sys-apps/pnpm-11.15.1, www-client/brave-browser-1.92.141), add(metadata/{md5-cache/app-editors/cursor-3.12.17, md5-cache/app-editors/devin-desktop-bin-3.5.17, md5-cache/app-editors/kiro-1.0.198, md5-cache/app-editors/trilium-0.104.0, md5-cache/app-editors/vim-9.2.0829, md5-cache/app-editors/vim-core-9.2.0829, md5-cache/app-editors/zed-1.13.0_pre20260717, md5-cache/app-editors/zed-1.13.0_pre20260722, md5-cache/app-emulation/crossover-bin-26.3.0, md5-cache/app-emulation/d7vk-2.0, md5-cache/app-misc/claude-desktop-bin-1.24012.1, md5-cache/app-portage/bentoolkit-0.14.0, md5-cache/dev-games/godot-4.8_alpha2, md5-cache/dev-lang/flutter-3.44.7, md5-cache/dev-libs/sentry-native-0.15.4, md5-cache/dev-python/uv-bin-0.11.31, md5-cache/dev-ruby/erb-6.0.6, md5-cache/dev-util/claude-agent-acp-plus-0.4.0, md5-cache/dev-util/claude-code-2.1.217, md5-cache/dev-util/codex-0.145.0, md5-cache/dev-util/codex-bin-0.145.0, md5-cache/dev-util/glslang-1.4.350.1_p20260721, md5-cache/dev-util/mesa_clc-26.2.0_pre20260722, md5-cache/dev-util/spirv-tools-1.4.350.0_p20260717, md5-cache/dev-util/vulkan-tools-1.4.354_p20260720, md5-cache/dev-vcs/gitkraken-12.3.1, md5-cache/mail-client/betterbird-bin-140.13.0, md5-cache/media-libs/mesa-26.2.0_pre20260722, md5-cache/media-libs/vulkan-layers-1.4.352_p20260721, md5-cache/media-libs/vulkan-loader-1.4.354_p20260720, md5-cache/net-misc/modemmanager-1.25.1_p20260721, md5-cache/net-misc/postman-bin-12.20.1, md5-cache/sci-ml/llama-cpp-0_pre10085, md5-cache/sys-apps/pnpm-11.15.1, md5-cache/www-client/brave-browser-1.92.141}), mod(metadata/{md5-cache/app-editors/vim-9.2.0782, md5-cache/app-emulation/crossover-bin-26.2.0, md5-cache/app-emulation/d7vk-1.12, md5-cache/app-portage/bentoolkit-0.13.1, md5-cache/dev-games/godot-4.8_alpha1, md5-cache/dev-util/glslang-1.4.350.1_p20260716, md5-cache/dev-util/mesa_clc-26.2.0_pre20260702, md5-cache/dev-util/mesa_clc-26.2.0_pre20260717, md5-cache/dev-util/spirv-tools-1.4.350.0_p20260716, md5-cache/dev-util/vulkan-tools-1.4.354_p20260715, md5-cache/media-libs/mesa-26.2.0_pre20260717, md5-cache/media-libs/vulkan-layers-1.4.352_p20260716, md5-cache/net-misc/modemmanager-1.25.1_p20260713}))
	SRC_URI="https://github.com/KhronosGroup/${MY_PN}/archive/${EGIT_COMMIT}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="amd64 arm arm64 ~loong ppc ppc64 ~riscv x86"
	S="${WORKDIR}"/${MY_PN}-${EGIT_COMMIT}
fi

DESCRIPTION="Vulkan Validation Layers"
HOMEPAGE="https://github.com/KhronosGroup/Vulkan-ValidationLayers"

LICENSE="Apache-2.0"
SLOT="0"
IUSE="wayland test X"
RESTRICT="!test? ( test ) test"

RDEPEND="dev-util/spirv-tools[${MULTILIB_USEDEP}]"
DEPEND="${RDEPEND}
	${PYTHON_DEPS}
	dev-util/glslang:=[${MULTILIB_USEDEP}]
	dev-util/spirv-headers
	dev-util/vulkan-headers
	>=dev-util/vulkan-utility-libraries-1.4.353-r1:=[${MULTILIB_USEDEP}]
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
