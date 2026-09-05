# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
PYTHON_COMPAT=( python3_{12..15} )

# BENTOO-DIVERGENCE: INHERIT - desktop, python-single-r1, unpacker and xdg,
# none of which ::gentoo pulls in.
#
# READ THIS FIRST, because it explains every other tag in this file: the two
# ebuilds do not package the same software. ::gentoo ships foldingathome-7.6.21,
# the old "fahclient" tarball. This is 8.5.6, a different client with a
# different upstream, a different licence and a different install layout. The
# parity sweep pairs them because the package names match, and almost every axis
# it reports as divergent follows from that one fact rather than from a decision
# taken here.
#
# The four eclasses map to what v8 actually is: unpacker because upstream ships
# .deb archives and no source tarball, desktop and xdg because v8 has a GUI and
# a .desktop entry where v7 was a daemon only, python-single-r1 because the
# control panel is Python.
inherit desktop python-single-r1 systemd unpacker xdg

DESCRIPTION="Folding@Home distributed computing client for protein folding research"
HOMEPAGE="https://foldingathome.org/"

BASE_URI="https://download.foldingathome.org/releases/public/fah-client"
SRC_URI="
	amd64? ( ${BASE_URI}/debian-10-64bit/release/fah-client_${PV}_amd64.deb -> ${P}-amd64.deb )
	arm64? ( ${BASE_URI}/debian-stable-arm64/release/fah-client_${PV}_arm64.deb -> ${P}-arm64.deb )
"
S="${WORKDIR}"

# BENTOO-DIVERGENCE: LICENSE - GPL-3, where ::gentoo declares
# "FAH-EULA-2014 FAH-special-permission". This looks alarming and is correct:
# Folding@home relicensed at v8. Verified against upstream on 2026-09-05 --
# github.com/FoldingAtHome/fah-client-bastet reports spdx_id GPL-3.0. The EULA
# pair belongs to the 7.6.x client ::gentoo still ships, not to this one.
#
# OPEN QUESTION, deliberately not resolved here because it is a licensing call
# for the maintainer: RESTRICT="bindist" below sits oddly next to GPL-3, which
# permits binary redistribution. It is defensible -- we ship a prebuilt .deb and
# redistributing GPL binaries obliges you to offer the matching source, which a
# binhost would not do on its own -- but it is currently unexplained. Either
# write the reason down or drop the token.
LICENSE="GPL-3"
SLOT="0"
# BENTOO-DIVERGENCE: KEYWORDS - "-*" plus the two arches upstream publishes a
# .deb for. The "-*" is not narrowing for its own sake: there is no source to
# build, so an arch with no .deb has nothing to install. SRC_URI names exactly
# amd64 and arm64.
KEYWORDS="-* ~amd64 ~arm64"
# elogind is default-on so the package still merges out of the box on a plain
# OpenRC profile. Neither flag is default there -- elogind comes from the
# desktop target and systemd from systemd profiles -- so without this default
# REQUIRED_USE refuses the merge on every headless/server amd64 profile. On a
# systemd profile elogind is USE-masked, so the default is overridden there and
# the exactly-one-of constraint still resolves.
# BENTOO-DIVERGENCE: IUSE - elogind/systemd (plus the python_single_target_*
# set that python-single-r1 generates). ::gentoo's 7.6.21 has no IUSE at all: it
# installs a systemd unit unconditionally. This overlay requires every daemon to
# be startable without systemd, so the two init systems are a choice here.
#
# BENTOO-DIVERGENCE: BDEPEND - dev-util/patchelf, needed only by the elogind
# path: the prebuilt .deb links libsystemd, so the elogind build rewrites that
# NEEDED entry rather than shipping a binary that pulls systemd in anyway.
IUSE="+elogind systemd"
REQUIRED_USE="^^ ( elogind systemd ) ${PYTHON_REQUIRED_USE}"
RESTRICT="bindist mirror strip"

# The prebuilt fah-client has a DT_NEEDED on libsystemd.so.0 and is BIND_NOW,
# so the loader aborts before main() unless that SONAME resolves. Only one of
# the two providers may be depended on: sys-auth/elogind carries an explicit
# !sys-apps/systemd blocker, so an unconditional dep would make the package
# unemergeable for every systemd user.
#
# liblz4.so.1 is DT_NEEDED on the same BIND_NOW binary, so it is the identical
# failure class as libsystemd.so.0 above -- the loader aborts before main()
# without it. Unlike libsystemd.so.0 there is only one provider and no USE
# flag to gate it behind, so app-arch/lz4 is unconditional.
#
# fahctl is a python3 script. It carries PEP 723 inline metadata declaring
# websocket-client, and the import is mandatory: the ImportError branch only
# prints a hint and exits 1, so without it the command is dead on arrival.
#
# fah-client speaks HTTPS to the assignment servers on startup, which needs a
# trusted CA bundle to validate the server certificate. Nothing else in this
# RDEPEND set necessarily pulls one in on a minimal headless or container
# host, so app-misc/ca-certificates is declared explicitly rather than left
# to arrive as a side effect of some other dependency.
#
# Upstream's .deb Depends lists libexpat1, but no libexpat.so* string exists
# anywhere in fah-client: not in DT_NEEDED, not among the lib*.so* string
# literals a dlopen call would need. fah-client does import dlopen/dlsym
# (from libdl.so.2, already DT_NEEDED); the only other lib*.so* names present
# are the optional CUDA/OpenCL/ROCm backends, out of scope by overlay policy,
# so a dlopen-based load of Expat was checked for and ruled out. What the
# string table does carry is Expat's own compiled-in material -- its license
# text, its internal version string "expat_2.2.6", an XML_DTD error message
# -- plus the mangled cbang adapter symbol cb::XML::ExpatAdapter. That is
# static linkage, not a missing runtime dependency, so dev-libs/expat is
# deliberately not declared; do not re-add it from the .deb's Depends without
# repeating this check.
#
# dev-libs/openssl:= was removed after the same check came back just as
# clean: no libssl.so*/libcrypto.so* in DT_NEEDED or in the string table, and
# upstream's own Depends never lists it either. What IS present is the
# CRYPTOGAMS perlasm identification strings ("... CRYPTOGAMS by
# <appro@openssl.org>"), an embedded "OpenSSL 1.1.1n 15 Mar 2022" version
# banner, and cbang/openssl/*.cpp source paths -- TLS is linked statically
# into fah-client. That is a live CVE-exposure fact, not just a build detail:
# a host-side openssl security update does not patch this binary, and
# dropping the := means Portage no longer even pretends a rebuild would help.
# A fix for a static-OpenSSL CVE here has to come from upstream re-releasing
# the .deb against a newer bundled OpenSSL.
#
# virtual/zlib:= replaces sys-libs/zlib:= -- pkgcheck flags the direct atom
# as deprecated.
# BENTOO-DIVERGENCE: RDEPEND - almost no overlap with ::gentoo's, for the reason
# in the header: v8 is a Python-fronted GUI client and v7 was a C++ daemon. Both
# lists are right for the thing they install.
#
# BENTOO-DIVERGENCE: DEFINED_PHASES - src_unpack and pkg_preinst, where ::gentoo
# defines pkg_config. src_unpack because a .deb is not something the default
# phase handles; pkg_preinst for the install-time checks that
# scripts/check-foldingathome-image.sh asserts against the built image.
RDEPEND="
	${PYTHON_DEPS}
	$(python_gen_cond_dep '
		dev-python/websocket-client[${PYTHON_USEDEP}]
	')
	acct-group/foldingathome
	acct-user/foldingathome
	app-arch/lz4
	app-misc/ca-certificates
	sys-libs/glibc
	virtual/zlib:=
	elogind? ( sys-auth/elogind )
	systemd? ( sys-apps/systemd )
"
BDEPEND="elogind? ( dev-util/patchelf )"

QA_PREBUILT="*"

src_install() {
	if use elogind; then
		# elogind ships libelogind.so.0 with the LIBSYSTEMD_<n> version nodes
		# and all seven sd_bus_* symbols fah-client imports, so this symlink
		# satisfies the loader's version check for real. A private RUNPATH
		# (not RPATH) keeps the override local to this binary and needs no
		# environment variable from the caller.
		dodir /opt/foldingathome/lib
		dosym "../../../usr/$(get_libdir)/libelogind.so.0" /opt/foldingathome/lib/libsystemd.so.0
		patchelf --set-rpath "${EPREFIX}/opt/foldingathome/lib" usr/bin/fah-client || die
	fi

	# Rewrite the upstream "#!/usr/bin/env python3" to the interpreter this
	# build selected, so fahctl runs on the exact implementation that
	# dev-python/websocket-client was installed for. Like the patchelf call
	# above, this edits the payload in ${S} before it is copied into the image.
	python_fix_shebang usr/bin/fahctl

	exeinto /opt/foldingathome
	doexe usr/bin/fah-client
	doexe usr/bin/fahctl

	dosym ../../opt/foldingathome/fah-client /usr/bin/fah-client
	dosym ../../opt/foldingathome/fahctl /usr/bin/fahctl

	keepdir /etc/fah-client
	keepdir /var/lib/fah-client
	keepdir /var/log/fah-client
	fowners foldingathome:foldingathome /etc/fah-client
	fowners foldingathome:foldingathome /var/lib/fah-client
	fowners foldingathome:foldingathome /var/log/fah-client

	newinitd "${FILESDIR}"/foldingathome-initd fah-client
	newconfd "${FILESDIR}"/foldingathome-confd fah-client
	systemd_dounit "${FILESDIR}"/fah-client.service

	insinto /usr/share/polkit-1/rules.d
	newins "${FILESDIR}"/10-fah-client.rules 10-fah-client.rules

	newicon usr/share/pixmaps/fahlogo.png fah-client.png
	make_desktop_entry "xdg-open https://app.foldingathome.org/" \
		"Folding@home Client" fah-client "Science;Biology;"

	dodoc usr/share/doc/fah-client/README.md
}

pkg_postinst() {
	xdg_pkg_postinst
	elog "To run Folding@home in the background at boot:"
	elog "  OpenRC:  rc-update add fah-client default"
	elog "  systemd: systemctl enable fah-client"
	elog ""
	elog "Access the web interface at http://localhost:7396"
	elog "Or use the official web app at https://app.foldingathome.org/"
}

pkg_postrm() {
	xdg_pkg_postrm
	elog "Folding@home data files in /var/lib/fah-client were not removed."
	elog "Remove them manually if no longer needed."
}
