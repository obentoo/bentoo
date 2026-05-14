# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..14} )
MULTILIB_ABIS="amd64 x86"
MULTILIB_COMPAT=( abi_x86_{32,64} )
inherit flag-o-matic meson-multilib python-any-r1

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/jp7677/dxvk-nvapi.git"
	EGIT_SUBMODULES=( external/{Vulkan-Headers,nvapi,vkroots,DirectX-Headers} )
else
	HASH_VULKAN=2cd90f9d20df57eac214c148f3aed885372ddcfe
	HASH_NVAPI=9b181ea572f680327fe01a14a0f1f41c78034104
	HASH_VKROOTS=ee76e620798612c52fb8dcc32a1058a0a3538930
	HASH_DXHEADERS=c94b9b23aaadc2034dd1cad656a5a69f1526f98a
	SRC_URI="
		https://github.com/jp7677/dxvk-nvapi/archive/refs/tags/v${PV}.tar.gz
			-> ${P}.tar.gz
		https://github.com/KhronosGroup/Vulkan-Headers/archive/${HASH_VULKAN}.tar.gz
			-> vulkan-headers-${HASH_VULKAN}.tar.gz
		https://github.com/NVIDIA/nvapi/archive/${HASH_NVAPI}.tar.gz
			-> nvidia-nvapi-${HASH_NVAPI}.tar.gz
		https://github.com/misyltoad/vkroots/archive/${HASH_VKROOTS}.tar.gz
			-> vkroots-${HASH_VKROOTS}.tar.gz
		https://github.com/microsoft/DirectX-Headers/archive/${HASH_DXHEADERS}.tar.gz
			-> directx-headers-${HASH_DXHEADERS}.tar.gz
	"
	KEYWORDS="~amd64"
fi

DESCRIPTION="Alternative NVAPI implementation for DXVK on Wine (DLSS, Reflex, ray tracing)"
HOMEPAGE="https://github.com/jp7677/dxvk-nvapi/"

LICENSE="MIT Apache-2.0"
SLOT="0"
IUSE="+abi_x86_32 crossdev-mingw +strip test"
RESTRICT="!test? ( test )"

BDEPEND="
	${PYTHON_DEPS}
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
		rmdir external/{Vulkan-Headers,nvapi,vkroots,DirectX-Headers} || die
		mv ../Vulkan-Headers-${HASH_VULKAN}    external/Vulkan-Headers   || die
		mv ../nvapi-${HASH_NVAPI}              external/nvapi            || die
		mv ../vkroots-${HASH_VKROOTS}          external/vkroots          || die
		mv ../DirectX-Headers-${HASH_DXHEADERS} external/DirectX-Headers || die
	fi

	# vcs_tag() runs `git describe` which fails without .git; pin literally.
	sed -i "s/@VCS_TAG@/v${PV}/" version.h.in || die

	default
}

src_configure() {
	use crossdev-mingw || PATH=${BROOT}/usr/lib/mingw64-toolchain/bin:${PATH}

	# LTO has caused random segfaults in DXVK family with mingw; filter for safety.
	filter-lto

	# -mavx and mingw-gcc do not mix safely.
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
		$(meson_use test enable_tests)
		$(usev strip --strip)
	)

	meson_src_configure
}

multilib_src_install_all() {
	dodoc README.md

	# Portage cannot strip PE/Windows DLLs; let meson --strip handle it.
	find "${ED}" -type f -name '*.a' -delete || die
}

pkg_postinst() {
	if [[ ! ${REPLACING_VERSIONS} ]]; then
		elog "${PN} installs nvapi64.dll (and nvapi.dll with USE=abi_x86_32) into"
		elog "${EROOT}/usr/lib/${PN}/x{64,32}/."
		elog
		elog "To use it with a Wine prefix, copy/symlink the DLLs into the prefix"
		elog "system32/syswow64 dirs and add them as overrides:"
		elog
		elog "	WINEPREFIX=/path/to/prefix wine reg add 'HKCU\\\\Software\\\\Wine\\\\DllOverrides' \\"
		elog "	    /v nvapi64 /d native /f"
		elog
		elog "Note: Proton and Proton-GE already bundle dxvk-nvapi — this package is"
		elog "intended for plain wine-vanilla / wine-staging setups."
	fi
}
