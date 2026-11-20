# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# HYBRID PACKAGING -- DO NOT "SIMPLIFY" THIS ON A VERSION BUMP.
#
# 1) Why the binaries come from the "embeddable" tarball and NOT from the .deb:
#
#    1a) THE REASON THAT OUTLIVES THE SONAMES -- the .deb's lemond links
#    libsystemd.so.0.  Measured 2026-08-08 on the 11.5.2 payload:
#       readelf -dW <deb>/usr/bin/lemond | grep NEEDED
#          libsystemd.so.0  libcap.so.2  libcpp-httplib.so.0.41  ...
#       imports: sd_bus_open_system sd_bus_call_method sd_bus_message_read
#                sd_bus_message_unref sd_bus_error_free sd_bus_unref
#                sd_pid_get_unit
#    DT_NEEDED is a hard load-time requirement, so that binary does not even
#    start on a host without systemd's libraries -- it merges cleanly, passes
#    QA, and then fails at exec on an OpenRC box.  That is the exact failure
#    sci-biology/foldingathome hit between 8.5.5 and 8.5.6.  The embeddable
#    lemond links neither libsystemd nor libcap (same command, same day).
#    This is listed FIRST because the soname reasons below are fixable --
#    someone could package cpp-httplib 0.41 -- and this one is not.  If a
#    future bump makes the .deb payload look tempting again, re-run the readelf
#    above before touching src_install.
#
#    1b) Debian-13 sonames.  Upstream's .deb (and the Fedora RPMs) link against
#    sonames that do not exist on Gentoo:
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
#    byte-identical for 11.5.0, and again for 2026.45.3 (backend_versions,
#    bench_scenarios, defaults,
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
	${LEMONADE_URI}/lemonade-server_${PV}-debian13_amd64.deb -> ${P}-data.deb
"

S="${WORKDIR}"

# resources/web-app/ holds the webpack chunks upstream ships prebuilt: React
# and KaTeX (MIT), highlight.js (BSD-3-Clause), DOMPurify (Apache-2.0 or
# MPL-2.0) and the vendored @google/model-viewer (Apache-2.0, with Lit
# BSD-3-Clause and three.js/fflate MIT), per the .LICENSE.txt files installed
# next to them; since 2026.45.3 the icons are Lucide (ISC) and Simple Icons
# (CC0-1.0) paths, per upstream's LICENSE.
LICENSE="Apache-2.0 BSD CC0-1.0 ISC MIT"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="+systemd"
RESTRICT="bindist mirror strip"

RDEPEND="
	!!sci-ml/lemonade
	acct-group/lemonade
	acct-user/lemonade
	app-arch/unzip
	app-arch/zstd:=
	|| (
		dev-libs/openssl-compat:3
		dev-libs/openssl:0/3
	)
	virtual/zlib:=
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

	# --- service files -----------------------------------------------------
	# One service per scope, mirroring the two units upstream ships.  Both are
	# installed UNCONDITIONALLY: an init script costs a systemd user nothing,
	# while gating it would leave an OpenRC user with no way to run the daemon.
	# Only the units are gated by USE=systemd.
	#
	# The system pair is byte-identical to sci-ml/lemonade's -- same
	# /usr/bin/lemond, same acct-user/lemonade -- because FILESDIR is
	# per-package and the file cannot be shared.  Keep them in sync.
	#
	# An earlier revision claimed no OpenRC service was possible here because
	# the units use StateDirectory and AmbientCapabilities.  That was wrong on
	# both counts: StateDirectory/RuntimeDirectory map onto `checkpath -d` in
	# start_pre(), which lemond.initd already does, and OpenRC does have a
	# `capabilities` variable (supervise-daemon --capabilities).
	#
	# CAP_SYS_RESOURCE is deliberately NOT set, and that is now a measurement
	# rather than a preference.  Run 2026-08-08: lemond started with zero
	# capabilities and RLIMIT_MEMLOCK soft = hard = 8 MiB, bound its HTTP and
	# WebSocket servers and built its 114-entry model cache, with no capability,
	# rlimit or memlock diagnostic.  Upstream's own systemd USER unit ships with
	# no AmbientCapabilities at all over the same ExecStart, so upstream already
	# runs this daemon without it in one of its two scopes.  The binary does
	# call setrlimit, so the capability is not decorative upstream -- it is what
	# would permit raising a HARD limit -- but the only memlock diagnostics in
	# it (memlock_ok, "Memlock limits are too low.") sit in an NPU-readiness
	# block next to npu_driver_ok and "NPU validation failed.", i.e. they report
	# a condition rather than gate startup.
	# NOT covered: the test host has no NPU, so that probe was never reached.
	# On a Ryzen AI box with a restrictive memlock ceiling the OpenRC answer is
	# an admin knob -- rc_ulimit="-l unlimited" in /etc/conf.d/lemond, or
	# /etc/security/limits.conf -- not a capability in this file.
	newinitd "${FILESDIR}"/lemond.initd lemond
	newconfd "${FILESDIR}"/lemond.confd lemond

	# User scope. newinitd has no user-scope variant, so the script is installed
	# as a plain executable, following sys-apps/xdg-desktop-portal.
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/lemond-user.initd lemond

	# --- systemd units -----------------------------------------------------
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
	# Read by the system unit via EnvironmentFile=-/etc/default/lemond.  The
	# .deb no longer ships etc/lemonade/conf.d/zz-secrets.conf (its postinst
	# migrates that directory into /etc/default/lemond).  0640: it carries
	# HF_TOKEN, LEMONADE_API_KEY and LEMONADE_ADMIN_API_KEY.
	insinto /etc/default
	doins etc/default/lemond
	fperms 0640 /etc/default/lemond
}

pkg_postinst() {
	elog "Start the system-wide server with one of:"
	elog "    rc-service lemond start"
	elog "    systemctl enable --now lemond.service"
	elog
	elog "Or run it as your own user (models land in ~/.cache/lemonade):"
	elog "    rc-service --user lemond start"
	elog "    systemctl --user enable --now lemond.service"
	elog
	elog "The web UI is served at http://localhost:13305/ once lemond is up."
	elog "API keys and HF_TOKEN belong in /etc/default/lemond"
	elog "for the systemd unit, or in /etc/conf.d/lemond for the OpenRC service."
	elog
	elog "Inference backends (llama.cpp, ROCm, vLLM, ...) are downloaded by"
	elog "lemond at runtime into its cache directory; they are not packaged."
}
