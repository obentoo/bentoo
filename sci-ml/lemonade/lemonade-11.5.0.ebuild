# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake multilib

# The web app (the browser UI served by lemond) is bundled with webpack, and
# upstream drives that through `npm ci` at build time.  That needs the network,
# so the dependency tree is shipped as a separate distfile generated from this
# release's src/web-app/package-lock.json with:
#   npm ci --ignore-scripts --no-audit --no-fund
#   tar caf lemonade-webapp-node_modules-${PV}.tar.xz node_modules
WEBAPP_NODE_MODULES="${PN}-webapp-node_modules-${PV}.tar.xz"

DESCRIPTION="Local LLM server with GPU and NPU acceleration"
HOMEPAGE="https://lemonade-server.ai/ https://github.com/lemonade-sdk/lemonade"
SRC_URI="
	https://github.com/lemonade-sdk/lemonade/archive/refs/tags/v${PV}.tar.gz
		-> ${P}.tar.gz
	webapp? ( https://distfiles.obentoo.org/${WEBAPP_NODE_MODULES} )
"

# The webapp bundle links the JavaScript dependency tree into
# renderer.bundle.js: React and KaTeX (MIT), highlight.js (BSD-3-Clause) and
# a handful of Apache-2.0 pieces, as listed in the .LICENSE.txt webpack emits
# next to the bundle.
LICENSE="Apache-2.0 webapp? ( BSD MIT )"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="+caps +systemd test +webapp"
RESTRICT="!test? ( test )"

# Everything upstream cannot find on the system is pulled in with FetchContent
# at configure time, which a sandboxed build cannot do, so all of these are
# hard dependencies rather than optional ones.  libdrm is not optional either:
# the Linux branch links drm_amdgpu unconditionally to read AMD GPU memory.
COMMON_DEPEND="
	>=app-arch/zstd-1.5.5:=
	>=dev-cpp/cpp-httplib-0.26.0:=
	>=net-libs/libwebsockets-4.3.3:=
	>=net-misc/curl-8.5.0:=
	net-libs/mbedtls:3=
	x11-libs/libdrm[video_cards_amdgpu]
	caps? ( sys-libs/libcap )
	systemd? ( sys-apps/systemd:= )
"
# cli11 and nlohmann_json are header-only.
DEPEND="
	${COMMON_DEPEND}
	>=dev-cpp/cli11-2.4.2
	>=dev-cpp/nlohmann_json-3.11.3
"
RDEPEND="
	${COMMON_DEPEND}
	acct-group/lemonade
	acct-user/lemonade
	app-arch/unzip
	!!sci-ml/lemonade-bin
"
BDEPEND="
	virtual/pkgconfig
	webapp? ( net-libs/nodejs[npm] )
"

PATCHES=(
	"${FILESDIR}"/${P}-webapp-prebuilt-node-modules.patch
)

src_unpack() {
	unpack "${P}.tar.gz"
	use webapp && unpack "${WEBAPP_NODE_MODULES}"
}

src_prepare() {
	cmake_src_prepare

	# libsystemd (journald log sink) and libcap (capability inheritance for the
	# backend processes lemond spawns) are probed with bare pkg_check_modules()
	# calls that have no option() to turn them off, so the detection itself has
	# to be neutralised or the build links them behind the USE flag's back.
	if ! use systemd; then
		sed -i -e 's/pkg_check_modules(SYSTEMD QUIET libsystemd)/set(SYSTEMD_FOUND FALSE)/' \
			CMakeLists.txt || die
	fi
	if ! use caps; then
		sed -i -e 's/pkg_check_modules(LIBCAP QUIET libcap)/set(LIBCAP_FOUND FALSE)/' \
			CMakeLists.txt || die
	fi

	# mbedtls (HTTPS and digest verification in the CLI) is looked up under its
	# upstream names, but Gentoo suffixes the slot onto everything it installs:
	# mbedtls-3.pc / libmbedtls-3.so, headers under /usr/include/mbedtls3.  The
	# probe therefore misses it and the fallback find_library() misses it too,
	# so point pkg-config at the slotted module names instead.  Keep this in
	# sync with the mbedtls slot in COMMON_DEPEND.
	sed -i -e 's/pkg_check_modules(MBEDTLS QUIET mbedtls mbedx509 mbedcrypto)/pkg_check_modules(MBEDTLS QUIET mbedtls-3 mbedx509-3 mbedcrypto-3)/' \
		src/cpp/cli/CMakeLists.txt || die

	# dev-cpp/cpp-httplib ships a CMake package config (httplib::httplib) but no
	# pkg-config file, while upstream only probes httplib through
	# pkg_search_module().  With no .pc the probe fails, USE_SYSTEM_HTTPLIB flips
	# to OFF and the build tries to FetchContent httplib, which the sandbox
	# cannot reach.  Synthesize the .pc the probe looks for (see the
	# PKG_CONFIG_PATH export in src_configure).  No feature macros in Cflags on
	# purpose: upstream's system branch skips them too, because they would turn
	# on header features needing link deps the interface target does not carry.
	local httplib_ver
	httplib_ver=$(sed -nE 's/.*CPPHTTPLIB_VERSION[[:space:]]+"([0-9.]+)".*/\1/p' \
		"${ESYSROOT}"/usr/include/httplib.h) || die
	[[ -n ${httplib_ver} ]] || die "could not read cpp-httplib version"
	mkdir -p "${T}"/pkgconfig || die
	cat > "${T}"/pkgconfig/httplib.pc <<-EOF || die
		prefix=${ESYSROOT}/usr
		libdir=\${prefix}/$(get_libdir)
		includedir=\${prefix}/include
		Name: httplib
		Description: cpp-httplib (Gentoo, synthesized by the ebuild)
		Version: ${httplib_ver}
		Cflags: -I\${includedir}
		Libs: -L\${libdir} -lcpp-httplib
	EOF
}

src_configure() {
	# Let pkg_search_module() find the httplib.pc synthesized in src_prepare.
	local -x PKG_CONFIG_PATH="${T}/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

	local mycmakeargs=(
		-DBUILD_TESTING=$(usex test)
		-DBUILD_WEB_APP=$(usex webapp)
		# The Tauri desktop shell and the AppIndicator tray are separate
		# products that would each need their own npm/cargo dependency set.
		-DBUILD_TAURI_APP=OFF
		-DREQUIRE_LINUX_TRAY=OFF
		# The web app bundles its own KaTeX from the node_modules distfile;
		# the system-modules path expects Debian's /usr/share/nodejs layout.
		-DUSE_SYSTEM_NODEJS_MODULES=OFF
		# Turn any dependency upstream failed to find into a configure-time
		# error instead of a silent download attempt.
		-DFETCHCONTENT_FULLY_DISCONNECTED=ON
	)

	cmake_src_configure
}

src_compile() {
	if use webapp; then
		# Consumed by the patch in src/web-app/BuildWebApp.cmake.
		local -x LEMONADE_PREBUILT_NODE_MODULES="${WORKDIR}/node_modules"
		# `npm run build` only spawns the bundled webpack, but keep npm from
		# touching the network or ${HOME} regardless.
		local -x npm_config_cache="${T}/npm-cache"
		local -x npm_config_offline=true
		local -x npm_config_audit=false
		local -x npm_config_fund=false
		local -x npm_config_update_notifier=false
	fi

	cmake_src_compile
}

src_install() {
	cmake_src_install

	# The service account comes from acct-user/lemonade and
	# acct-group/lemonade, so the sysusers.d drop-in only duplicates them.
	rm -r "${ED}"/usr/lib/sysusers.d || die

	newinitd "${FILESDIR}"/lemond.initd lemond
	newconfd "${FILESDIR}"/lemond.confd lemond

	# /var/lib/lemonade is created at first start, not here: the lemonade
	# service account does not exist on the build host, so fowners by name would
	# fail.  systemd's StateDirectory= and the initd's checkpath both create it
	# owned by lemonade:lemonade on startup.
}

pkg_postinst() {
	elog "lemond stores models and its config.json under /var/lib/lemonade."
	elog "Start it with one of:"
	elog "    rc-service lemond start"
	elog "    systemctl start lemond.service"
	elog
	elog "Inference backends (llama.cpp, whisper.cpp, vLLM, ONNX Runtime,"
	elog "Ryzen AI/NPU, ...) are not built here: lemond downloads and manages"
	elog "them at runtime, which is why app-arch/unzip is a runtime dependency."
	elog
	elog "Set LEMONADE_API_KEY and HF_TOKEN in /etc/lemonade/conf.d/ for the"
	elog "systemd unit, or in /etc/conf.d/lemond for the OpenRC service."
}
