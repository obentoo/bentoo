# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit kernel-install toolchain-funcs unpacker verify-sig

# Pre-built sys-kernel/bentoo-kernel-${PV}. The binary package comes from
# scripts/build-bentoo-kernel-bin.sh, which builds that ebuild with a fixed
# USE set (bore sched-ext, no lto, no hardened, no debug) and a clean
# configuration, and is hosted on distfiles.obentoo.org.
#
# PROVISIONAL: the binary is built with GCC, without ThinLTO. A clang build
# would make every out-of-tree module (nvidia-drivers, ...) need clang and
# lld of the exact LLVM major the kernel was built with, on every user's
# machine. Revisit once that requirement can be carried (e.g. a pinned
# llvm-core/clang slot in RDEPEND).
#
# Modules are signed with a key discarded after the build, and
# CONFIG_MODULE_SIG_FORCE is off (unlike kernel-build's modules-sign default):
# without Secure Boot, out-of-tree modules load with a taint; under Secure
# Boot, lockdown enforces signatures and only a MOK-enrolled key works.
#
# The sources below only feed modules_prepare, which out-of-tree modules
# build against, so they must be the tree the binary was built from, patch
# for patch: keep CACHY_REL, PATCHSET, BORE_COMMIT, BIGK_COMMIT,
# INTEL_PATCHES and INTEL_PATCHES_REBASED (and the files/ they name)
# identical to sys-kernel/bentoo-kernel-${PV}.
CACHY_REL=1
MY_P=cachyos-${PV}-${CACHY_REL}
PATCHSET=linux-gentoo-patches-7.3.1
BORE_COMMIT=f3770b16d069a1bce8dfa63841042137f8b43434
BIGK_COMMIT=4c1de6a96a691ceca60fc2c2f61de9710e43e395
INTEL_PATCHES=(
	0001-drm-i915-vrr-Check-TRANS_PUSH_SEND-after-DSB-commit.patch
	0002-drm-xe-mcr-Wait-for-steering-semaphore-before-lock.patch
	0003-drm-xe-mcr-Sanitize-steer-semaphore-on-resume.patch
	0010-brost-scope-lnl-flush-wa.patch
	0101-drm-xe-Capture-devcoredump-on-TLB-invalidation-timeo.patch
	0102-drm-xe-Log-when-a-timed-out-TLB-invalidation-ack-fin.patch
	0103-drm-xe-Implement-Wa_22016122933.patch
	0104-drm-xe-Map-Wa_22016122933-buffers-WC-on-the-CPU-side.patch
)
INTEL_PATCHES_REBASED=(
	0002-drm-xe-mcr-Wait-for-steering-semaphore-before-lock.patch
)
# BINPKG is ${PF} of the source ebuild, the directory inside the gpkg;
# BINPKG_ID is Portage's build id, which only the file name carries. A
# rebuild of the same ebuild bumps the id, a revbump of it changes BINPKG.
BINPKG=bentoo-kernel-${PV}
BINPKG_ID=1
BINPKG_FILE=${BINPKG}-${BINPKG_ID}.amd64.gpkg.tar

DESCRIPTION="Pre-built Linux kernel from CachyOS sources with Gentoo and bentoo patches"
HOMEPAGE="
	https://github.com/CachyOS/linux
	https://wiki.gentoo.org/wiki/Project:Distribution_Kernel
"
# Distfile names are shared with sys-kernel/bentoo-kernel on purpose: a
# machine that has both downloads the sources once.
SRC_URI="
	https://github.com/CachyOS/linux/releases/download/${MY_P}/${MY_P}.tar.gz
	https://distfiles.gentoo.org/pub/proj/dist-kernel/patchsets/$(ver_cut 1-2 "${PATCHSET##*-}")/${PATCHSET}.tar.xz
	https://raw.githubusercontent.com/CachyOS/kernel-patches/${BORE_COMMIT}/$(ver_cut 1-2)/sched/0001-bore-cachy.patch
		-> bentoo-kernel-${BORE_COMMIT:0:8}-bore-cachy.patch
	https://distfiles.obentoo.org/${BINPKG_FILE}
	verify-sig? (
		https://github.com/CachyOS/linux/releases/download/${MY_P}/${MY_P}.tar.gz.asc
	)
"
for _p in "${INTEL_PATCHES[@]}"; do
	has "${_p}" "${INTEL_PATCHES_REBASED[@]}" && continue
	SRC_URI+="
		https://raw.githubusercontent.com/big-comm/big-kernel/${BIGK_COMMIT}/linux-big/${_p}
			-> bentoo-kernel-${BIGK_COMMIT:0:8}-${_p}
	"
done
unset _p
S=${WORKDIR}

KEYWORDS="~amd64"
# No USE=generic-uki (KERNEL_IUSE_GENERIC_UKI is unset): a generic UKI embeds
# an initramfs assembled from the build machine's binaries, which would have
# to be built for x86-64-v3 first. The initramfs is generated on the user's
# machine, as for sys-kernel/bentoo-kernel.
IUSE="modules-compress"

# Same pin as sys-kernel/bentoo-kernel, see there. pkgcheck reports the
# second alternative of the newest version as NonexistentDeps, by design.
RDEPEND="
	|| (
		~virtual/dist-kernel-${PV}
		>sys-kernel/bentoo-kernel-bin-${PV}-r9999
	)
	modules-compress? ( sys-apps/kmod[lzma] )
"
PDEPEND="
	>=virtual/dist-kernel-${PV}
"
BDEPEND="
	app-alternatives/bc
	app-alternatives/lex
	app-alternatives/yacc
	dev-util/pahole
	sys-libs/binutils-libs
	virtual/libelf
	verify-sig? ( sec-keys/openpgp-keys-cachyos )
"

KV_LOCALVERSION='-bentoo-dist-bin'
KV_FULL=${PV}${KV_LOCALVERSION}

QA_PREBUILT='*'

VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/cachyos.asc

src_unpack() {
	if use verify-sig; then
		verify-sig_verify_detached \
			"${DISTDIR}/${MY_P}.tar.gz" "${DISTDIR}/${MY_P}.tar.gz.asc"
	fi

	unpacker "${MY_P}.tar.gz" "${PATCHSET}.tar.xz" "${BINPKG_FILE}"
}

src_prepare() {
	cd "${MY_P}" || die
	eapply "${WORKDIR}/${PATCHSET}"
	eapply "${DISTDIR}/bentoo-kernel-${BORE_COMMIT:0:8}-bore-cachy.patch"

	local p
	for p in "${INTEL_PATCHES[@]}"; do
		if has "${p}" "${INTEL_PATCHES_REBASED[@]}"; then
			eapply "${FILESDIR}/$(ver_cut 1-2)-${p}"
		else
			eapply "${DISTDIR}/bentoo-kernel-${BIGK_COMMIT:0:8}-${p}"
		fi
	done

	default
}

src_configure() {
	# force ld.bfd if we can find it easily
	local HOSTLD="$(tc-getBUILD_LD)"
	if type -P "${HOSTLD}.bfd" &>/dev/null; then
		HOSTLD+=.bfd
	fi
	local LD="$(tc-getLD)"
	if type -P "${LD}.bfd" &>/dev/null; then
		LD+=.bfd
	fi
	tc-export_build_env
	local makeargs=(
		V=1
		WERROR=0

		HOSTCC="$(tc-getBUILD_CC)"
		HOSTCXX="$(tc-getBUILD_CXX)"
		HOSTLD="${HOSTLD}"
		HOSTAR="$(tc-getBUILD_AR)"
		HOSTCFLAGS="${BUILD_CFLAGS}"
		HOSTLDFLAGS="${BUILD_LDFLAGS}"

		CROSS_COMPILE=${CHOST}-
		AS="$(tc-getAS)"
		CC="$(tc-getCC)"
		LD="${LD}"
		AR="$(tc-getAR)"
		NM="$(tc-getNM)"
		STRIP="$(tc-getSTRIP)"
		OBJCOPY="$(tc-getOBJCOPY)"
		OBJDUMP="$(tc-getOBJDUMP)"
		READELF="$(tc-getREADELF)"

		# we need to pass it to override colliding Gentoo envvar
		ARCH="$(tc-arch-kernel)"

		O="${WORKDIR}"/modprep
	)

	local kernel_dir="${BINPKG}/image/usr/src/linux-${KV_FULL}"
	[[ -s ${kernel_dir}/.config ]] ||
		die "${BINPKG} holds no linux-${KV_FULL}: built with another LOCALVERSION?"

	mkdir modprep || die
	cp "${kernel_dir}/.config" modprep/ || die
	emake -C "${MY_P}" "${makeargs[@]}" modules_prepare
}

src_test() {
	local kernel_dir="${BINPKG}/image/usr/src/linux-${KV_FULL}"
	kernel-install_test "${KV_FULL}" \
		"${WORKDIR}/${kernel_dir}/$(dist-kernel_get_image_path)" \
		"${BINPKG}/image/lib/modules/${KV_FULL}" \
		"${WORKDIR}/${kernel_dir}/.config"
}

src_install() {
	local rel_kernel_dir=/usr/src/linux-${KV_FULL}
	local kernel_dir="${BINPKG}/image${rel_kernel_dir}"

	# Overwrite the identifier in the prebuilt package
	echo "${CATEGORY}/${PF}:${SLOT}" > "${kernel_dir}/dist-kernel" || die

	mv "${BINPKG}"/image/{lib,usr} "${ED}"/ || die

	# strip out-of-source build stuffs from modprep
	# and then copy built files
	find modprep -type f '(' \
			-name Makefile -o \
			-name '*.[ao]' -o \
			'(' -name '.*' -a -not -name '.config' ')' \
		')' -delete || die
	rm modprep/source || die
	cp -p -R modprep/. "${ED}${rel_kernel_dir}"/ || die

	# Update timestamps on all modules to ensure cleanup works correctly
	# when switching USE=modules-compress.
	find "${ED}/lib" -name '*.ko' -exec touch {} + || die

	# Modules were already stripped before signing
	dostrip -x /lib/modules
	kernel-install_compress_modules
}

pkg_postinst() {
	kernel-install_pkg_postinst

	ewarn "This kernel trusts only the throwaway key its modules were signed with."
	ewarn "Out-of-tree modules (nvidia-drivers, ...) signed with your own key will"
	ewarn "not load under Secure Boot unless that key is enrolled as a Machine"
	ewarn "Owner Key (mokutil --import, through shim). Without Secure Boot they"
	ewarn "load as usual. To embed your own key, use sys-kernel/bentoo-kernel."
}
