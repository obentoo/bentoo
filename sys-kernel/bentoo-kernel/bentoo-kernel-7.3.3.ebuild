# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

KERNEL_IUSE_GENERIC_UKI=1
LLVM_COMPAT=( {19..23} )
LLVM_OPTIONAL=1
# scripts/min-tool-version.sh of 7.3; bindgen is pinned below for the same reason.
RUST_MIN_VER="1.85.0"
RUST_OPTIONAL=1
RUST_REQ_USE="rust-src"

inherit kernel-build llvm-r2 rust toolchain-funcs verify-sig

# Layers, applied in this order on top of kernel.org ${PV}:
#  1. CachyOS source release ${MY_P}: kernel.org plus CachyOS's topic
#     branches (cachy tweaks, gaming-sched, ADIOS, BBRv3, amd-pstate,
#     HDMI VRR, T2 Macs, ...). One signed tarball, rebased by CachyOS.
#  2. Gentoo's dist-kernel patchset, the one sys-kernel/gentoo-kernel-${PV}
#     uses. 0008 creates the "Gentoo Linux" Kconfig menu.
#  3. BORE (USE=bore), from CachyOS's kernel-patches. Not in the tarball:
#     CachyOS's own default is plain EEVDF.
#  4. Intel Xe/i915 fixes for Arrow Lake and Meteor Lake, carried by
#     big-comm/big-kernel while they are under review upstream.
#
# A CachyOS respin of the same kernel (cachyos-${PV}-N) is a revbump here,
# not a PV change: virtual/dist-kernel matches dist kernels by PV, so PV
# must stay equal to the kernel.org version.
#
# A new series (e.g. 7.2 -> 7.3) moves more than PV: the Gentoo patchset and
# configs, the BORE path ($(ver_cut 1-2)/sched/ in kernel-patches, which may
# not exist yet when CachyOS ships the series), every INTEL_PATCHES entry,
# the ".autoupdate/packages.toml" pattern, and sys-kernel/bentoo-kernel-bin,
# which has to be rebuilt from this ebuild (scripts/build-bentoo-kernel-bin.sh).
CACHY_REL=1
MY_P=cachyos-${PV}-${CACHY_REL}
# Keep these four in step with sys-kernel/gentoo-kernel-${PV}.
PATCHSET=linux-gentoo-patches-7.3.1
CONFIG_VER=7.3.1-gentoo
GENTOO_CONFIG_P=gentoo-kernel-config-g19
# Last commit touching $(ver_cut 1-2)/sched/0001-bore-cachy.patch.
BORE_COMMIT=f3770b16d069a1bce8dfa63841042137f8b43434
# big-comm/big-kernel commit the Intel patches are taken from, in the order
# its PKGBUILD applies them. Drop each one once a kernel release has it: on
# a bump, a patch that fails forward but applies with -R is already in.
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
# big-kernel tracks one series behind; these no longer apply to this one and
# come rebased from files/$(ver_cut 1-2)-<name>, in the same position. Drop an
# entry once big-kernel moves to this series.
#  0002: 7.3 turned drm_WARN_ON_ONCE(&xe->drm, ...) into
#        xe_gt_WARN_ON_ONCE(gt, ...) on a line the patch removes.
INTEL_PATCHES_REBASED=(
	0002-drm-xe-mcr-Wait-for-steering-semaphore-before-lock.patch
)

DESCRIPTION="Linux kernel built from CachyOS sources with Gentoo and bentoo patches"
HOMEPAGE="
	https://github.com/CachyOS/linux
	https://wiki.gentoo.org/wiki/Project:Distribution_Kernel
"
SRC_URI="
	https://github.com/CachyOS/linux/releases/download/${MY_P}/${MY_P}.tar.gz
	https://distfiles.gentoo.org/pub/proj/dist-kernel/patchsets/$(ver_cut 1-2 "${PATCHSET##*-}")/${PATCHSET}.tar.xz
	https://gitweb.gentoo.org/proj/dist-kernel/gentoo-kernel-config.git/snapshot/${GENTOO_CONFIG_P}.tar.bz2
	https://distfiles.gentoo.org/pub/proj/dist-kernel/config/fedora-kernel-config-${CONFIG_VER}.tar.xz
	bore? (
		https://raw.githubusercontent.com/CachyOS/kernel-patches/${BORE_COMMIT}/$(ver_cut 1-2)/sched/0001-bore-cachy.patch
			-> ${PN}-${BORE_COMMIT:0:8}-bore-cachy.patch
	)
	verify-sig? (
		https://github.com/CachyOS/linux/releases/download/${MY_P}/${MY_P}.tar.gz.asc
	)
"
for _p in "${INTEL_PATCHES[@]}"; do
	has "${_p}" "${INTEL_PATCHES_REBASED[@]}" && continue
	SRC_URI+="
		https://raw.githubusercontent.com/big-comm/big-kernel/${BIGK_COMMIT}/linux-big/${_p}
			-> ${PN}-${BIGK_COMMIT:0:8}-${_p}
	"
done
unset _p
S=${WORKDIR}/${MY_P}

KEYWORDS="~amd64"
IUSE="+bore debug hardened +lto rust +sched-ext"
# Rust cannot be combined with BTF under LTO (sched-ext and debug turn BTF
# on): since 7.3.3 init/Kconfig accepts the mix, but the Rust modules get no
# BTF from pahole and modfinal fails. Nor with the GCC RANDSTRUCT plugin
# (hardened without lto merges hardened-gcc-plugins.config), which
# init/Kconfig still drops CONFIG_RUST for without a word.
REQUIRED_USE="
	lto? ( ${LLVM_REQUIRED_USE} )
	rust? (
		lto? ( !sched-ext !debug )
		!lto? ( !hardened )
	)
"

BDEPEND="
	debug? ( dev-util/pahole )
	rust? (
		${RUST_DEPEND}
		>=dev-util/bindgen-0.71.1
	)
	lto? (
		$(llvm_gen_dep '
			llvm-core/clang:${LLVM_SLOT}
			llvm-core/lld:${LLVM_SLOT}
			llvm-core/llvm:${LLVM_SLOT}
		')
	)
	sched-ext? ( dev-util/pahole )
	verify-sig? ( sec-keys/openpgp-keys-cachyos )
"
# Holds virtual/dist-kernel at this kernel's PV until a newer bentoo-kernel
# exists. ::gentoo bumps the virtual as soon as gentoo-kernel moves, and
# without this Portage satisfies the newer virtual by pulling gentoo-kernel
# onto a bentoo-kernel machine. Once a newer bentoo-kernel is installed this
# slot no longer pins anything, so old kernels can stay side by side.
# pkgcheck reports the second alternative of the newest version as
# NonexistentDeps: it names a version that does not exist yet, by design.
RDEPEND="
	|| (
		~virtual/dist-kernel-${PV}
		>sys-kernel/bentoo-kernel-${PV}-r9999
	)
"
PDEPEND="
	>=virtual/dist-kernel-${PV}
"

QA_FLAGS_IGNORED="
	usr/src/linux-.*/scripts/gcc-plugins/.*.so
	usr/src/linux-.*/vmlinux
"
# Assembled with .incbin of the certificate blobs; clang's integrated
# assembler emits no .note.GNU-stack for it. Build-tree object kept for
# out-of-tree modules, never loaded or executed.
QA_EXECSTACK="usr/src/linux-*/certs/system_certificates.o"

VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/cachyos.asc

pkg_setup() {
	kernel-build_pkg_setup

	# Puts the selected slot's rustc first in PATH, where the kernel's
	# scripts/rust_is_available.sh looks for it.
	use rust && [[ ${MERGE_TYPE} != binary ]] && rust_pkg_setup

	if use lto && [[ ${MERGE_TYPE} != binary ]]; then
		llvm-r2_pkg_setup
		# kernel-build takes the toolchain from tc-get*, and forces ld.bfd
		# when it finds one; ThinLTO needs clang with ld.lld. Exporting here
		# also makes tc-is-gcc false in src_prepare, so the GCC-only
		# hardening plugins config is not merged into a clang build.
		export CC=clang CXX=clang++ LD=ld.lld AR=llvm-ar NM=llvm-nm \
			OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump READELF=llvm-readelf \
			STRIP=llvm-strip
	fi
}

# Portage carries exported variables into every later phase, and the
# post-merge ones run the system's own tools: dracut builds the UKI with
# `${OBJDUMP:-objdump} -h`, parses GNU's column layout, and dies on
# llvm-objdump's ("16#: invalid integer constant"). Give those phases the
# default toolchain back.
_bentoo-kernel_drop_llvm_env() {
	unset CC CXX LD AR NM OBJCOPY OBJDUMP READELF STRIP
}

pkg_preinst() {
	_bentoo-kernel_drop_llvm_env
	kernel-install_pkg_preinst
}

pkg_postinst() {
	_bentoo-kernel_drop_llvm_env
	kernel-build_pkg_postinst

	# Same PV as gentoo-kernel means virtual/dist-kernel's subslot does not
	# move, so Portage rebuilds no out-of-tree module on its own.
	elog "Out-of-tree modules (nvidia-drivers, virtualbox-modules, ...) are not"
	elog "rebuilt automatically for this kernel. Point /usr/src/linux at it and"
	elog "rebuild them:"
	elog "  eselect kernel set linux-${PV}-bentoo-dist$(usev hardened -hardened)"
	elog "  emerge --oneshot @module-rebuild"
	elog "Those packages hold modules for ONE kernel at a time: the rebuild drops"
	elog "them from the kernel /usr/src/linux pointed at before. Keep a binary"
	elog "package of them (quickpkg) to switch back without compiling."

	# Under Secure Boot the kernel only loads modules signed by a key it
	# trusts. Without MODULES_SIGN_KEY it trusts a throwaway key generated by
	# this build, so modules built later with your own key are rejected.
	if use modules-sign && [[ -z ${MODULES_SIGN_KEY} ]]; then
		ewarn "Out-of-tree modules signed with your own key will not load on this"
		ewarn "kernel under Secure Boot or CONFIG_MODULE_SIG_FORCE. Set"
		ewarn "MODULES_SIGN_KEY and MODULES_SIGN_CERT for ${CATEGORY}/${PN} AND for"
		ewarn "every module package (nvidia-drivers, ...) through package.env, then"
		ewarn "rebuild this kernel and run emerge @module-rebuild."
	fi
}

pkg_postrm() {
	_bentoo-kernel_drop_llvm_env
	kernel-install_pkg_postrm
}

pkg_config() {
	_bentoo-kernel_drop_llvm_env
	kernel-install_pkg_config
}

src_unpack() {
	if use verify-sig; then
		verify-sig_verify_detached \
			"${DISTDIR}/${MY_P}.tar.gz" "${DISTDIR}/${MY_P}.tar.gz.asc"
	fi

	unpack "${MY_P}.tar.gz" "${PATCHSET}.tar.xz" \
		"${GENTOO_CONFIG_P}.tar.bz2" "fedora-kernel-config-${CONFIG_VER}.tar.xz"
}

src_prepare() {
	eapply "${WORKDIR}/${PATCHSET}"
	if use bore; then
		eapply "${DISTDIR}/${PN}-${BORE_COMMIT:0:8}-bore-cachy.patch"
	fi

	local p
	for p in "${INTEL_PATCHES[@]}"; do
		if has "${p}" "${INTEL_PATCHES_REBASED[@]}"; then
			eapply "${FILESDIR}/$(ver_cut 1-2)-${p}"
		else
			eapply "${DISTDIR}/${PN}-${BIGK_COMMIT:0:8}-${p}"
		fi
	done

	default

	# CONFIG_CACHY turns the split lock mitigation off (the deliberate
	# slowdown of a process that issues split locks); detection and its
	# dmesg warning stay either way. bentoo keeps mainline's default of on;
	# sysctl kernel.split_lock_mitigate=0 switches it off at runtime.
	local sld='static unsigned int sysctl_sld_mitigate = 0;'
	grep -qF "${sld}" arch/x86/kernel/cpu/bus_lock.c ||
		die "split lock default moved in the CachyOS tree; re-check ${FUNCNAME}"
	sed -i -e "s/^${sld}\$/static unsigned int sysctl_sld_mitigate = 1;/" \
		arch/x86/kernel/cpu/bus_lock.c || die

	cp "${WORKDIR}/fedora-kernel-config-${CONFIG_VER}/kernel-x86_64-fedora.config" \
		.config || die

	local myversion="-bentoo-dist"
	use hardened && myversion+="-hardened"
	echo "CONFIG_LOCALVERSION=\"${myversion}\"" > "${T}"/version.config || die
	local dist_conf_path="${WORKDIR}/${GENTOO_CONFIG_P}"

	local merge_configs=(
		"${T}"/version.config
		"${dist_conf_path}"/base.config
		"${dist_conf_path}"/6.12+.config
	)
	use debug || merge_configs+=( "${dist_conf_path}"/no-debug.config )
	if use hardened; then
		merge_configs+=(
			"${dist_conf_path}"/hardened-base.config
			"${dist_conf_path}"/hardened-amd64.config
		)
		tc-is-gcc && merge_configs+=( "${dist_conf_path}"/hardened-gcc-plugins.config )
	fi
	use secureboot && merge_configs+=(
		"${dist_conf_path}"/secureboot.config
		"${dist_conf_path}"/zboot.config
	)

	# bentoo's layer goes last, so it wins over Fedora's and Gentoo's.
	# kernel-build_merge_configs still appends /etc/kernel/config.d/*.config
	# after it, so users keep the final word.
	merge_configs+=( "${FILESDIR}"/bentoo-base.config )
	use lto && merge_configs+=( "${FILESDIR}"/lto.config )
	# kCFI stands in for the GCC hardening plugins a clang build cannot use.
	use hardened && use lto && merge_configs+=( "${FILESDIR}"/cfi.config )
	use bore && merge_configs+=( "${FILESDIR}"/bore.config )
	use sched-ext && merge_configs+=( "${FILESDIR}"/sched-ext.config )
	if use rust; then
		merge_configs+=( "${FILESDIR}"/rust.config )
	else
		merge_configs+=( "${FILESDIR}"/no-rust.config )
	fi

	kernel-build_merge_configs "${merge_configs[@]}"
}

src_configure() {
	kernel-build_src_configure

	# Fail instead of shipping a kernel that silently lost what a USE flag
	# promised: a Kconfig dependency can drop an option without a word
	# (no-debug.config dropping BTF took sched_ext with it).
	local required=(
		CONFIG_GENERIC_CPU=y
		CONFIG_X86_64_VERSION=3
		CONFIG_CACHY=y
		CONFIG_GENTOO_LINUX=y
		CONFIG_HZ_1000=y
		CONFIG_PREEMPT_DYNAMIC=y
	)
	use lto && required+=( CONFIG_CC_IS_CLANG=y CONFIG_LTO_CLANG_THIN=y )
	use hardened && use lto && required+=( CONFIG_CFI=y )
	use bore && required+=( CONFIG_SCHED_BORE=y )
	use sched-ext && required+=( CONFIG_DEBUG_INFO_BTF=y CONFIG_SCHED_CLASS_EXT=y )
	if use rust; then
		required+=( CONFIG_RUST=y CONFIG_DRM_PANIC_SCREEN_QR_CODE=y )
	else
		required+=( "# CONFIG_RUST is not set" )
	fi

	local opt missing=()
	for opt in "${required[@]}"; do
		grep -qx -- "${opt}" "${WORKDIR}"/modprep/.config || missing+=( "${opt}" )
	done
	if [[ ${#missing[@]} -gt 0 ]]; then
		eerror "The resolved kernel config lost options this build promises:"
		eerror "  ${missing[*]}"
		eerror "If /etc/kernel/config.d disables one on purpose, turn off the"
		eerror "matching USE flag instead."
		die "required kernel options missing: ${missing[*]}"
	fi
}
