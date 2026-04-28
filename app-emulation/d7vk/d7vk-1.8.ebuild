# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )
MULTILIB_ABIS="amd64 x86"
MULTILIB_COMPAT=( abi_x86_{32,64} )
inherit eapi9-ver flag-o-matic meson-multilib python-any-r1

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/WinterSnowfall/d7vk.git"
	EGIT_SUBMODULES=(
		include/{native/directx,spirv,vulkan}
		subprojects/{libdisplay-info,dxbc-spirv}
		subprojects/dxbc-spirv/submodules/spirv_headers
	)
else
	HASH_DIRECTX=adeef0e68c3471e13a9028528bbe0d835345424a
	HASH_SPIRV=04f10f650d514df88b76d25e83db360142c7b174
	HASH_VULKAN=5d94bb4dcc968cccce1f601324fcaf3eda92a52b
	HASH_DXBCSPIRV=29c93aeecd55533a357fdd7c95be5587d1c1f506
	HASH_SPIRV_DXBC=c8ad050fcb29e42a2f57d9f59e97488f465c436d
	HASH_DISPLAYINFO=275e6459c7ab1ddd4b125f28d0440716e4888078
	SRC_URI="
		https://github.com/WinterSnowfall/d7vk/archive/refs/tags/v${PV}.tar.gz
			-> ${P}.tar.gz
		https://github.com/WinterSnowfall/mingw-directx-headers/archive/${HASH_DIRECTX}.tar.gz
			-> mingw-directx-headers-${HASH_DIRECTX}.tar.gz
		https://github.com/KhronosGroup/SPIRV-Headers/archive/${HASH_SPIRV}.tar.gz
			-> spirv-headers-${HASH_SPIRV}.tar.gz
		https://github.com/KhronosGroup/SPIRV-Headers/archive/${HASH_SPIRV_DXBC}.tar.gz
			-> spirv-headers-${HASH_SPIRV_DXBC}.tar.gz
		https://github.com/KhronosGroup/Vulkan-Headers/archive/${HASH_VULKAN}.tar.gz
			-> vulkan-headers-${HASH_VULKAN}.tar.gz
		https://github.com/doitsujin/dxbc-spirv/archive/${HASH_DXBCSPIRV}.tar.gz
			-> dxbc-spirv-${HASH_DXBCSPIRV}.tar.gz
		https://github.com/doitsujin/libdisplay-info/archive/${HASH_DISPLAYINFO}.tar.gz
			-> libdisplay-info-${HASH_DISPLAYINFO}.tar.gz
	"
	KEYWORDS="-* ~amd64 ~x86"
fi

DESCRIPTION="Vulkan-based implementation of D3D7 and earlier APIs for Linux/Wine, fork of DXVK"
HOMEPAGE="https://github.com/WinterSnowfall/d7vk"

# Reuse setup script from upstream DXVK (d7vk does not ship its own)
SRC_URI+=" https://raw.githubusercontent.com/doitsujin/dxvk/cd21cd7fa3b0df3e0819e21ca700b7627a838d69/setup_dxvk.sh"

LICENSE="ZLIB Apache-2.0 MIT"
SLOT="0"
IUSE="+abi_x86_32 crossdev-mingw +ddraw +d3d8 +d3d9 +d3d10 +d3d11 +dxgi +strip"
REQUIRED_USE="
	|| ( ddraw d3d8 d3d9 d3d10 d3d11 dxgi )
	d3d8? ( d3d9 )
	d3d10? ( d3d11 )
	d3d11? ( dxgi )
"

BDEPEND="
	${PYTHON_DEPS}
	dev-util/glslang
	!crossdev-mingw? ( dev-util/mingw64-toolchain[${MULTILIB_USEDEP}] )
"

pkg_pretend() {
	[[ ${MERGE_TYPE} == binary ]] && return

	if use crossdev-mingw && [[ ! -v MINGW_BYPASS ]]; then
		local tool=-w64-mingw32-g++
		for tool in $(usev abi_x86_64 x86_64${tool}) $(usev abi_x86_32 i686${tool}); do
			if ! type -P ${tool} >/dev/null; then
				eerror "With USE=crossdev-mingw, it is necessary to setup the mingw toolchain."
				eerror "For instructions, please see: https://wiki.gentoo.org/wiki/Mingw"
				use abi_x86_32 && use abi_x86_64 &&
					eerror "Also, with USE=abi_x86_32, will need both i686 and x86_64 toolchains."
				die "USE=crossdev-mingw is set but ${tool} was not found"
			elif [[ ! $(LC_ALL=C ${tool} -v 2>&1) =~ "Thread model: posix" ]]; then
				eerror "${PN} requires GCC to be built with --enable-threads=posix"
				eerror "Please see: https://wiki.gentoo.org/wiki/Mingw#POSIX_threads_for_Windows"
				die "USE=crossdev-mingw is set but ${tool} does not use POSIX threads"
			fi
		done
	fi
}

src_prepare() {
	if [[ ${PV} != 9999 ]]; then
		rmdir include/native/directx include/spirv include/vulkan \
			subprojects/libdisplay-info subprojects/dxbc-spirv || die
		mv ../mingw-directx-headers-${HASH_DIRECTX} include/native/directx || die
		mv ../SPIRV-Headers-${HASH_SPIRV} include/spirv || die
		mv ../Vulkan-Headers-${HASH_VULKAN} include/vulkan || die
		mv ../dxbc-spirv-${HASH_DXBCSPIRV} subprojects/dxbc-spirv || die
		rmdir subprojects/dxbc-spirv/submodules/spirv_headers || die
		mv ../SPIRV-Headers-${HASH_SPIRV_DXBC} subprojects/dxbc-spirv/submodules/spirv_headers || die
		mv ../libdisplay-info-${HASH_DISPLAYINFO} subprojects/libdisplay-info || die
	fi
	cp -- "${DISTDIR}"/setup_dxvk.sh "${S}"/setup_d7vk.sh || die

	default

	sed -i "/^basedir=/s|=.*|=${EPREFIX}/usr/lib/${PN}|" setup_d7vk.sh || die
}

src_configure() {
	use crossdev-mingw || PATH=${BROOT}/usr/lib/mingw64-toolchain/bin:${PATH}

	# random segfaults reported with LTO in some games (matches DXVK guidance)
	filter-lto

	# -mavx and mingw-gcc do not mix safely
	# https://github.com/doitsujin/dxvk/issues/4746#issuecomment-2708869202
	append-flags -mno-avx

	if [[ ${CHOST} != *-mingw* ]]; then
		if [[ ! -v MINGW_BYPASS ]]; then
			unset AR CC CXX RC STRIP
			filter-flags '-fuse-ld=*'
			filter-flags '-mfunction-return=thunk*' #878849
			filter-flags '-Wl,-z,*' #928038
		fi

		CHOST_amd64=x86_64-w64-mingw32
		CHOST_x86=i686-w64-mingw32
		CHOST=$(usex x86 ${CHOST_x86} ${CHOST_amd64})

		strip-unsupported-flags
	fi

	multilib-minimal_src_configure
}

multilib_src_configure() {
	use crossdev-mingw && [[ ! -v MINGW_BYPASS ]] && unset AR CC CXX RC STRIP

	local emesonargs=(
		--prefix="${EPREFIX}"/usr/lib/${PN}
		--{bin,lib}dir=x${MULTILIB_ABI_FLAG: -2}
		--force-fallback-for=libdisplay-info
		$(meson_use {,enable_}ddraw)
		$(meson_use {,enable_}d3d8)
		$(meson_use {,enable_}d3d9)
		$(meson_use {,enable_}d3d10)
		$(meson_use {,enable_}d3d11)
		$(meson_use {,enable_}dxgi)
		$(usev strip --strip)
	)

	meson_src_configure
}

multilib_src_install_all() {
	dobin setup_d7vk.sh
	dodoc README.md

	find "${ED}" -type f -name '*.a' -delete || die
}

pkg_postinst() {
	if [[ ! ${REPLACING_VERSIONS} ]]; then
		elog "To enable ${PN} on a wine prefix, you can run the following command:"
		elog
		elog "	WINEPREFIX=/path/to/prefix setup_d7vk.sh install --symlink"
		elog
		elog "See ${EROOT}/usr/share/doc/${PF}/README.md* for details."
		elog "Note: setup_d7vk.sh is provided as an adapted copy of DXVK's setup_dxvk.sh,"
		elog "since d7vk does not ship its own helper script upstream."
	fi
}
