# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# HYBRID PACKAGING -- DO NOT "SIMPLIFY" THIS ON A VERSION BUMP.
#
# 1) Why the binaries come from the "embeddable" tarball and NOT from the .deb:
#    Upstream's .deb (and the Fedora RPMs) link against Debian-13 sonames that
#    do not exist on Gentoo:
#       libcpp-httplib.so.0.41  -- Gentoo builds cpp-httplib as .so.0.50.1
#       libwebsockets.so.19     -- Gentoo ships libwebsockets.so.21
#       libmbedcrypto.so.16     -- Gentoo installs this as libmbedcrypto-3.so.16
#    The "embeddable" tarball links those statically and only needs libraries
#    Gentoo provides under the very same soname (verified with readelf -d):
#       libz.so.1 libzstd.so.1 libssl.so.3 libcrypto.so.3 libdrm_amdgpu.so.1
#       libstdc++.so.6 libm.so.6 libgcc_s.so.1 libc.so.6
#
# 2) Why the .deb is still fetched (unconditionally, amd64 flavour only):
#    Only *arch-independent data* is taken out of it -- never an ELF object.
#    The embeddable tarball omits the web UI, the JSON schemas, the examples,
#    the man pages, the systemd units and architecture_defaults.json.  Those
#    files carry no machine code, so the amd64 .deb serves every arch and can
#    stay outside the SRC_URI USE-conditionals.
#    The six resources/*.json present in BOTH archives were verified
#    byte-identical for 11.5.0 (backend_versions, bench_scenarios, defaults,
#    server_models, toolDefinitions, vllm_model_config), so the .deb copy is
#    used for the whole resources/ tree -- it is a strict superset of the
#    tarball's.  Re-check that with cmp before trusting it on the next bump.
#
# 3) Why the ELF payload lives in /usr/$(get_libdir)/lemonade-server and NOT
#    directly in /usr/bin:
#    The embeddable build resolves its data files as <dirname /proc/self/exe>/
#    resources/ ONLY.  Unlike the .deb build it has no /usr/share/lemonade-server
#    fallback compiled in -- grep both binaries: that string is present in the
#    .deb one and absent from the embeddable one.  Installed straight into
#    /usr/bin it dies at startup with
#       Error: Failed to open /usr/bin/resources/defaults.json
#    So the real executables sit next to a "resources" symlink pointing at the
#    arch-independent tree under /usr/share/lemonade-server, and /usr/bin only
#    carries symlinks (/proc/self/exe resolves through them to the real path,
#    so the lookup still lands in the right directory).

inherit multilib systemd unpacker

DESCRIPTION="Local LLM server with GPU and NPU acceleration (prebuilt binaries)"
HOMEPAGE="https://lemonade-server.ai/
	https://github.com/lemonade-sdk/lemonade"

MY_EMB="lemonade-embeddable-${PV}-ubuntu"
LEMONADE_URI="https://github.com/lemonade-sdk/lemonade/releases/download/v${PV}"

SRC_URI="
	amd64? ( ${LEMONADE_URI}/${MY_EMB}-x64.tar.gz -> ${P}-amd64.tar.gz )
	arm64? ( ${LEMONADE_URI}/${MY_EMB}-arm64.tar.gz -> ${P}-arm64.tar.gz )
	${LEMONADE_URI}/lemonade-server_${PV}-debian13_amd64.deb -> ${P}-data.deb
"

S="${WORKDIR}"

# resources/web-app/renderer.bundle.js is the webpack bundle upstream ships
# prebuilt: React and KaTeX (MIT), highlight.js (BSD-3-Clause) and some
# Apache-2.0 pieces, per the .LICENSE.txt installed next to it.
LICENSE="Apache-2.0 BSD MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="+systemd"
RESTRICT="bindist mirror strip"

RDEPEND="
	!!sci-ml/lemonade
	acct-group/lemonade
	acct-user/lemonade
	app-arch/unzip
	app-arch/zstd:=
	dev-libs/openssl:0/3
	sys-libs/zlib:=
	x11-libs/libdrm[video_cards_amdgpu]
"
# ar(1) comes from binutils (@system); xz-utils decompresses the deb data.tar.xz.
BDEPEND="app-arch/xz-utils"

QA_PREBUILT="*"

# src_unpack comes from unpacker.eclass: it routes the .tar.gz through the
# normal unpacker and the .deb through unpack_deb (ar + data.tar.xz), so no
# override is needed here.

src_install() {
	local libdir="/usr/$(get_libdir)/lemonade-server"
	local datadir="/usr/share/lemonade-server"
	local emb

	if use amd64; then
		emb="${WORKDIR}/${MY_EMB}-x64"
	elif use arm64; then
		emb="${WORKDIR}/${MY_EMB}-arm64"
	else
		die "unsupported ARCH=${ARCH}: no embeddable tarball for it"
	fi

	# --- ELF payload (arch dependent, from the embeddable tarball) ---------
	exeinto "${libdir}"
	doexe "${emb}/lemonade"
	doexe "${emb}/lemond"

	# --- arch-independent resources (from the .deb) ------------------------
	insinto "${datadir}"
	doins -r usr/share/lemonade-server/resources

	# The binaries look for "<exedir>/resources"; point that at the shared
	# tree so the data is installed FHS-correctly but still found at runtime.
	dosym -r "${datadir}/resources" "${libdir}/resources"

	# User-facing commands.
	dosym -r "${libdir}/lemonade" /usr/bin/lemonade
	dosym -r "${libdir}/lemond" /usr/bin/lemond

	# lemond additionally probes this absolute path as a system-wide defaults
	# file (hardcoded string "/usr/share/lemonade/defaults.json").  It is
	# byte-identical to resources/defaults.json; ship it so it resolves.
	insinto /usr/share/lemonade
	doins usr/share/lemonade/defaults.json

	# Examples keep upstream's layout: they are referenced from the docs and
	# some are meant to be run, so no dodoc compression.
	insinto "${datadir}"
	doins -r usr/share/lemonade-server/examples
	fperms +x "${datadir}/examples/migrate-to-systemd.sh"

	# --- man pages ---------------------------------------------------------
	# The .deb ships them pre-gzipped; portage does its own compression and
	# warns about compressed files in docompress-ed directories, so unpack
	# them first.
	gunzip usr/share/man/man1/lemonade.1.gz usr/share/man/man1/lemond.1.gz || die
	doman usr/share/man/man1/lemonade.1
	doman usr/share/man/man1/lemond.1

	# --- systemd units -----------------------------------------------------
	# USE=systemd gates only the unit files: upstream ships no OpenRC service
	# and the units rely on systemd-only directives (StateDirectory,
	# AmbientCapabilities=CAP_SYS_RESOURCE), so they are dead weight elsewhere.
	# acct-user/acct-group stay unconditional -- the daemon is meant to run
	# under a dedicated account however it is started.
	if use systemd; then
		systemd_dounit usr/lib/systemd/system/lemond.service
		systemd_douserunit usr/lib/systemd/user/lemond.service
	fi
	# upstream's sysusers.d drop-in is deliberately not installed: the account
	# comes from acct-user/lemonade and acct-group/lemonade, same as in
	# sci-ml/lemonade.

	# --- configuration -----------------------------------------------------
	# Read by the unit via EnvironmentFile=-/etc/lemonade/conf.d/*.conf
	insinto /etc/lemonade/conf.d
	doins etc/lemonade/conf.d/zz-secrets.conf
}

pkg_postinst() {
	elog "Start the system-wide server with:"
	elog "    systemctl enable --now lemond.service"
	elog
	elog "Or run it as your own user (models land in ~/.cache/lemonade):"
	elog "    systemctl --user enable --now lemond.service"
	elog
	elog "The web UI is served at http://localhost:13305/ once lemond is up."
	elog "API keys and HF_TOKEN belong in /etc/lemonade/conf.d/zz-secrets.conf."
	elog
	elog "Inference backends (llama.cpp, ROCm, vLLM, ...) are downloaded by"
	elog "lemond at runtime into its cache directory; they are not packaged."
}
