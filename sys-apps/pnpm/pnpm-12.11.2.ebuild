# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Fast, disk space efficient package manager"
HOMEPAGE="https://pnpm.io"

# TWO distfiles, and the second one is where pnpm actually lives.
#
# pnpm 12 is a rewrite: the implementation moved from a JavaScript bundle to a
# native Rust binary, and the "pnpm" package on npm stopped carrying it.  What
# that tarball ships now is a wrapper -- a shebang-less placeholder bin, the
# Corepack entry points under bin/, and dist/, which holds node-gyp and the
# downloader behind https://get.pnpm.io.  There is no JS implementation left in
# it to fall back to: run the wrapper without the binary and it fetches one over
# the network on first use and writes it next to itself, which is not something
# an installed package may do.
#
# The binary is published per platform as an optional dependency of that
# wrapper, so it is fetched here as a distfile instead.  The npm basenames
# ("exe.linux-x64-12.3.4.tgz") are too generic for a shared DISTDIR, hence the
# rename.
SRC_URI="
	https://registry.npmjs.org/${PN}/-/${P}.tgz
	amd64? (
		elibc_glibc? (
			https://registry.npmjs.org/@pnpm/exe.linux-x64/-/exe.linux-x64-${PV}.tgz
				-> ${PN}-exe.linux-x64-${PV}.tgz
		)
		elibc_musl? (
			https://registry.npmjs.org/@pnpm/exe.linux-x64-musl/-/exe.linux-x64-musl-${PV}.tgz
				-> ${PN}-exe.linux-x64-musl-${PV}.tgz
		)
	)
	arm64? (
		elibc_glibc? (
			https://registry.npmjs.org/@pnpm/exe.linux-arm64/-/exe.linux-arm64-${PV}.tgz
				-> ${PN}-exe.linux-arm64-${PV}.tgz
		)
		elibc_musl? (
			https://registry.npmjs.org/@pnpm/exe.linux-arm64-musl/-/exe.linux-arm64-musl-${PV}.tgz
				-> ${PN}-exe.linux-arm64-musl-${PV}.tgz
		)
	)
"
S="${WORKDIR}/wrapper/package"

# The Rust binary vendors its dependency tree; THIRD-PARTY-NOTICES.md ships
# alongside it and is installed with the rest of the wrapper.
LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# Prebuilt, and upstream ships it stripped already.
QA_PREBUILT="usr/lib*/node_modules/${PN}/${PN}"
RESTRICT="strip"

# The floor comes from upstream, not from what happens to be installed here:
# pnpm 12.3.4's package.json declares engines.node ">=18.*".
#
# Node.js is no longer what runs pnpm -- the native binary needs nothing -- but
# it is what pnpm spawns for a package's lifecycle scripts and for node-gyp, so
# a Node.js-less pnpm could install a tree and not build it.  This is RDEPEND
# only: nothing is compiled here.
#
# The :* slot operator is load-bearing.  Story 005 made net-libs/nodejs slotted
# by major (this overlay carries SLOT="24" and SLOT="26"; ::gentoo keeps the
# unslotted SLOT="0/<major>"), so a slotless atom matches more than one slot and
# pkgcheck rejects it as MissingSlotDep.  pnpm runs any node past the floor, so
# ":*" -- any slot, no rebuild when it changes -- is the honest constraint.
# Pinning one major would be a lie.
#
# ACCEPTED QA FINDING: pkgcheck reports NonsolvableDepsInDev on the
# default/linux/amd64/23.0/x32 dev profile.  net-libs/nodejs is unavailable on
# amd64/x32 -- ::gentoo states exactly that and package.mask's each consumer
# individually there (dev-util/claude-code, net-misc/sunshine,
# app-containers/devcontainer, ...).  Every nodejs consumer in this overlay
# reports it (playwright, lemonade, claude-agent-acp-tui), so it is a property
# of the profile, not of this ebuild.  The systemic fix is one overlay-wide
# profiles/arch/amd64/x32/package.mask covering all of them.
RDEPEND=">=net-libs/nodejs-18:*"

# Basename of the native-binary distfile for this host, matching the SRC_URI
# above.  Both axes are USE_EXPAND_IMPLICIT flags (ARCH, ELIBC), which is why
# neither appears in IUSE.
pnpm_native_distfile() {
	local arch libc=

	if use amd64; then
		arch="x64"
	elif use arm64; then
		arch="arm64"
	else
		die "no prebuilt pnpm binary for ARCH=${ARCH}"
	fi

	use elibc_musl && libc="-musl"

	echo "${PN}-exe.linux-${arch}${libc}-${PV}.tgz"
}

src_unpack() {
	# Both tarballs unpack to "package/", so they cannot share a directory.
	mkdir -p "${WORKDIR}"/{wrapper,native} || die

	cd "${WORKDIR}/wrapper" || die
	unpack "${P}.tgz"

	cd "${WORKDIR}/native" || die
	unpack "$(pnpm_native_distfile)"
}

src_compile() {
	:
}

src_install() {
	local install_dir="/usr/$(get_libdir)/node_modules/${PN}" b

	# Everything that exists to obtain a binary we already have.  install.js
	# links the native binary over the placeholder (done below, at merge time
	# instead), bin/ is Corepack's Node.js entry point, and it reaches
	# dist/node_modules/get-pnpm to download a binary when none is installed.
	# Left in place, that download path stays reachable in an installed
	# package; taken out, the only pnpm here is the one Portage merged.
	rm -r bin install.js native-binary.mjs dist/node_modules/get-pnpm || die

	insinto "${install_dir}"
	doins -r .

	# What upstream's install.js does on Unix: replace the shebang-less `pnpm`
	# placeholder -- which only exists to hand over to the Node.js wrapper --
	# with the native binary.  It has to land at this path rather than straight
	# in /usr/bin because the binary resolves dist/node-gyp-bin relative to
	# itself when it builds a lifecycle script's PATH.
	exeinto "${install_dir}"
	newexe "${WORKDIR}/native/package/${PN}" "${PN}"

	# pn/pnpx/pnx stay the committed `#!/bin/sh` scripts upstream ships: they
	# `exec pnpm [dlx]`, and the binary's own launch-name detection does not
	# substitute for them.  Measured: a `pnpx` symlink onto the binary prints
	# pnpm's help, not dlx's.
	fperms +x "${install_dir}"/{pn,pnpx,pnx}
	fperms +x "${install_dir}/dist/node-gyp-bin/node-gyp"
	fperms +x "${install_dir}/dist/node_modules/node-gyp/bin/node-gyp.js"

	# No fperms on the symlinks themselves: chmod follows a symlink, so it
	# would silently alter the target instead, and a symlink's own mode is
	# meaningless to the kernel.
	for b in "${PN}" pn pnpx pnx; do
		dosym "../$(get_libdir)/node_modules/${PN}/${b}" "/usr/bin/${b}"
	done
}
