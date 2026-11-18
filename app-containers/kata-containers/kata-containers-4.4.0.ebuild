# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Workspace rust-version is 1.95; rust-toolchain.toml pins 1.96 for upstream CI.
RUST_MIN_VER="1.95.0"

inherit cargo linux-info toolchain-funcs

DESCRIPTION="Lightweight VMs that run containers with the isolation of a hypervisor"
HOMEPAGE="https://katacontainers.io/ https://github.com/kata-containers/kata-containers"
# Upstream publishes the whole dependency tree with each release: crates.io,
# the seven git crates and the Go vendor tree. Nothing has to be regenerated
# on a bump beyond the distfile itself.
SRC_URI="
	https://github.com/kata-containers/kata-containers/archive/refs/tags/${PV}.tar.gz
		-> ${P}.tar.gz
	https://github.com/kata-containers/kata-containers/releases/download/${PV}/${P}-vendor.tar.gz
"

LICENSE="Apache-2.0"
# Dependent crate licenses, surveyed with `cargo tree --format {l}` over
# runtime-rs, kata-ctl and kata-agent[seccomp,init-data] for 4.2.0. Only the
# licenses that are not an "OR" alternative to one already listed are named.
# Redo the survey on every bump: the version moves, this list does not.
LICENSE+="
	Apache-2.0 BSD CDLA-Permissive-2.0 ISC MIT MIT-0 MPL-2.0 Unicode-3.0 ZLIB
"
SLOT="0"
KEYWORDS="~amd64"
IUSE="+seccomp"
# The suite needs root, KVM and a running containerd; upstream runs it in CI
# containers, not from a build sandbox.
RESTRICT="test"

# The agent and the libraries it links are copied into the guest initrd, so a
# soname change in any of them must rebuild the image.
DEPEND="
	elibc_glibc? ( sys-libs/glibc:= )
	elibc_musl? ( sys-libs/musl:= )
	seccomp? ( sys-libs/libseccomp:= )
"
# QEMU is the only hypervisor this ebuild configures. Firecracker in runtime-rs
# cannot boot an initrd, and dragonball needs Kata's dragonball-experimental
# guest kernel; both wait for a disk-image rootfs.
RDEPEND="
	${DEPEND}
	app-emulation/virtiofsd
	~sys-kernel/kata-guest-kernel-6.18.35_p202
	|| (
		app-containers/containerd
		app-containers/cri-o
	)
	amd64? ( app-emulation/qemu[qemu_softmmu_targets_x86_64,vhost-net] )
"
BDEPEND="
	app-arch/libarchive
	app-misc/pax-utils
	dev-build/cmake
"

QA_FLAGS_IGNORED="
	usr/bin/containerd-shim-kata-v2
	usr/bin/kata-ctl
	usr/share/kata-containers/.*
"
# The initrd carries a copy of the host's dynamic loader and libraries for the
# guest, which is the point of building it here.
QA_PREBUILT="usr/share/kata-containers/*"

CONFIG_CHECK="~KVM ~VHOST_VSOCK ~VHOST_NET ~TUN"
ERROR_KVM="Kata needs KVM to start its guest VMs."
ERROR_VHOST_VSOCK="The runtime reaches the in-guest agent over vhost-vsock."

KATA_SHARE="/usr/share/kata-containers"
KATA_INITRD="${KATA_SHARE}/kata-containers-initrd.img"

pkg_setup() {
	linux-info_pkg_setup
	rust_pkg_setup
}

src_unpack() {
	# The vendor tarball is rooted at the source tree: ./vendor (crates),
	# ./.cargo/config.toml (git source replacements) and src/runtime/vendor (Go).
	unpack "${P}.tar.gz"
	tar -xzf "${DISTDIR}/${P}-vendor.tar.gz" -C "${S}" || die
	# The project's .cargo/config.toml outranks CARGO_HOME and already points
	# crates-io and the git sources at ./vendor. The eclass's own "gentoo"
	# source stays on its empty default dir: two sources on one directory is
	# an error in cargo.
	mkdir -p "${ECARGO_VENDOR}" || die
	cargo_gen_config
}

kata_arch() {
	case ${ARCH} in
		amd64) echo x86_64 ;;
		arm64) echo aarch64 ;;
		*) die "unsupported ARCH: ${ARCH}" ;;
	esac
}

# The Makefiles are used only for their sed-based generators. Their build
# rules pin RUSTFLAGS to "--deny warnings" inline, which drops the toolchain
# flags Portage sets and turns every new rustc lint into a build failure.
kata_make() {
	# Portage exports ARCH=amd64; the Makefiles want the uname -m spelling.
	emake ARCH="$(kata_arch)" LIBC=gnu PREFIX=/usr BINDIR=/usr/bin "$@"
}

src_configure() {
	kata_make -C src/agent src/version.rs
	kata_make -C src/tools/kata-ctl src/ops/version.rs
	kata_make -C src/runtime-rs crates/shim/src/config.rs \
		config/configuration-qemu-runtime-rs.toml

	# The guest rootfs is an initrd built below, not a disk image; the two keys
	# are mutually exclusive in the hypervisor section.
	local conf=src/runtime-rs/config/configuration-qemu-runtime-rs.toml
	local from="image = \"${KATA_SHARE}/kata-containers.img\""
	grep -qxF "${from}" "${conf}" || die "image key not found in ${conf}"
	sed -i "s|^${from}\$|initrd = \"${KATA_INITRD}\"|" "${conf}" || die

	cargo_src_configure
}

src_compile() {
	cargo_src_compile -p runtime-rs -p kata-ctl

	local features=( init-data $(usev seccomp) )
	cargo_src_compile -p kata-agent --features "${features[*]}"

	kata_build_initrd
}

# The guest rootfs: the agent runs as PID 1 (Kata's AGENT_INIT=yes), so the
# VM carries no init system at all, and the agent mounts /proc, /sys, /dev and
# /run itself. What is copied in is the agent plus the shared objects it links,
# taken from this system. The archive is written from an mtree manifest so the
# root ownership and /dev/console node need no privileges.
kata_build_initrd() {
	local root="${WORKDIR}/rootfs" agent
	agent="$(cargo_target_dir)/kata-agent"
	[[ -x ${agent} ]] || die "kata-agent was not built"

	# Start from nothing on every run: anything left over would be archived.
	rm -rf "${root}" || die
	mkdir -p "${root}"/{dev,etc,proc,run,sbin,sys,tmp,usr/bin,usr/$(get_libdir)} || die
	cp "${agent}" "${root}/usr/bin/kata-agent" || die
	# Portage strips what it installs, not what is packed inside a file it
	# installs; unstripped, the agent alone is ~34 MiB of every guest's RAM.
	if ! has nostrip ${FEATURES} && ! has strip ${RESTRICT}; then
		$(tc-getSTRIP) --strip-unneeded "${root}/usr/bin/kata-agent" || die
	fi

	# lddtree -l prints the binary first, then the loader and every library
	# it resolves. The loader keeps its path (it is hardcoded in PT_INTERP);
	# libraries go flat into the default search directory, because the guest
	# has no ld.so.cache to find e.g. libgcc_s under /usr/lib/gcc.
	local -a libs
	local lib
	mapfile -t libs < <(lddtree -l "${agent}" | tail -n +2)
	[[ ${#libs[@]} -gt 0 ]] || die "lddtree found no libraries for kata-agent"
	for lib in "${libs[@]}"; do
		# glibc names it ld-linux*, musl ld-musl-*.
		if [[ ${lib##*/} == ld-linux* || ${lib##*/} == ld-musl-* ]]; then
			cp -L --parents "${lib}" "${root}/" || die
		else
			cp -L "${lib}" "${root}/usr/$(get_libdir)/" || die
		fi
	done
	echo kata > "${root}/etc/hostname" || die

	# Parents must precede children in the archive: the kernel's initramfs
	# unpacker does not create missing directories.
	local spec="${WORKDIR}/initrd.mtree" path rel mode
	{
		echo "#mtree"
		echo "/set uid=0 gid=0 time=0.0"
		while IFS= read -r -d '' path; do
			rel=".${path#"${root}"}"
			if [[ -L ${path} ]]; then
				echo "${rel} type=link link=$(readlink "${path}")"
			elif [[ -d ${path} ]]; then
				echo "${rel} type=dir mode=0755"
			else
				mode=0644
				[[ -x ${path} ]] && mode=0755
				echo "${rel} type=file mode=${mode} contents=${path}"
			fi
		done < <(find "${root}" -mindepth 1 -print0 | sort -z)
		echo "./dev/console type=char device=native,5,1 mode=0600"
		echo "./init type=link link=/usr/bin/kata-agent"
		echo "./sbin/init type=link link=/usr/bin/kata-agent"
	} > "${spec}" || die

	bsdtar --format newc -cf - "@${spec}" | gzip -9n > "${WORKDIR}/initrd.img" ||
		die "failed to write the initrd"
	# A guest that cannot exec its init panics before any log reaches the
	# host, so check the archive here instead.
	bsdtar -tf "${WORKDIR}/initrd.img" | grep -qx "./usr/bin/kata-agent" ||
		die "initrd lacks the agent"
}

src_install() {
	local target
	target="$(cargo_target_dir)"
	dobin "${target}"/{containerd-shim-kata-v2,kata-ctl}

	insinto "${KATA_SHARE}"
	newins "${WORKDIR}/initrd.img" "${KATA_INITRD##*/}"

	insinto /usr/share/defaults/kata-containers/runtime-rs
	doins src/runtime-rs/config/configuration-qemu-runtime-rs.toml
	dosym configuration-qemu-runtime-rs.toml \
		/usr/share/defaults/kata-containers/runtime-rs/configuration.toml

	dodoc README.md
}

pkg_postinst() {
	elog "Check that this host can run Kata guests with:"
	elog "  kata-ctl check all"
	elog "On x86_64 that check only knows Intel CPUs in ${PV}: on AMD it reports"
	elog "missing GenuineIntel/vmx even when KVM works."
	elog "The host-to-guest vsock fails with ENODEV while vmw_vsock_vmci_transport"
	elog "(VMware guest/host support) is loaded alongside vhost_vsock."
	elog "Containerd picks the shim up by runtime name, for example:"
	elog "  nerdctl run --runtime io.containerd.kata.v2 --rm alpine uname -r"
	elog "Local changes belong in /etc/kata-containers/runtime-rs/configuration.toml,"
	elog "which takes precedence over the defaults in"
	elog "/usr/share/defaults/kata-containers/runtime-rs/."
}
