# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
# linux/debian/control and linux/mozillavpn.spec both require cargo >= 1.91.
RUST_MIN_VER="1.91.0"

inherit cmake go-env linux-info python-any-r1 rust systemd xdg

DESCRIPTION="Mozilla VPN client: Qt desktop app, root WireGuard daemon and SOCKS proxy"
HOMEPAGE="
	https://vpn.mozilla.org/
	https://github.com/mozilla-mobile/mozilla-vpn-client
"
# Upstream's own source release, the one its Debian/RPM packaging and the AUR
# build from. It is a wrapper around the Debian source package; the
# mozillavpn_<ver>~rc<stamp>.orig.tar.gz inside carries every git submodule,
# the cargo crates (3rdparty/cargo-vendor) and the Go modules of the netfilter
# library (linux/netfilter/vendor), so the build needs no network. The GitHub
# tag tarball has none of that. The ~rc<stamp> is the release-branch build the
# tag points at: apart from dotfiles and the stripped linux/debian and
# linux/mozillavpn.spec templates, its tree is identical to tag v${PV}.
SRC_URI="https://archive.mozilla.org/pub/vpn/releases/${PV}/source/mozillavpn-sources.tar.gz
	-> ${P}-sources.tar.gz"

# MPL-2.0 for the client (LICENSE.md). Bundled and linked in:
# embeddable-wg-library from wireguard-tools (LGPL-2.1+), c-ares (MIT, static,
# used by the SOCKS proxy).
LICENSE="MPL-2.0 LGPL-2.1+ MIT"
# Rust crates of mozillavpn-obfuscator and the signature library, from
# `cargo tree -e normal,build --target x86_64-unknown-linux-gnu`
LICENSE+=" Apache-2.0 ISC MIT Unicode-3.0"
# Go modules of the netfilter library (google/nftables, mdlayher/*,
# golang.org/x/*, josharian/native, go-cmp)
LICENSE+=" Apache-2.0 BSD MIT"
SLOT="0"
KEYWORDS="~amd64"
IUSE="systemd"

# qtbase is bound with := because the client builds against Qt private
# headers (Qt6::GuiPrivate, for the XDG portal parent window on Wayland).
COMMON_DEPEND="
	dev-libs/glib:2
	dev-qt/qtbase:6=[dbus,gui,network,ssl,widgets,xml]
	dev-qt/qtdeclarative:6
	dev-qt/qtnetworkauth:6
	dev-qt/qtsvg:6
	dev-qt/qtwebsockets:6
	sys-auth/polkit
"
DEPEND="${COMMON_DEPEND}"
# The client talks to the daemon over the system bus; the daemon is started by
# D-Bus activation or by the init script/unit.
RDEPEND="
	${COMMON_DEPEND}
	sys-apps/dbus
"
BDEPEND="
	${PYTHON_DEPS}
	>=dev-lang/go-1.21
	dev-qt/qttools:6[linguist]
	virtual/pkgconfig
	$(python_gen_any_dep 'dev-python/pyyaml[${PYTHON_USEDEP}]')
"

# Rust (cargo driven by CMake, not cargo.eclass) does not take the toolchain
# LDFLAGS.
QA_FLAGS_IGNORED="usr/bin/mozillavpn-obfuscator"

# The daemon drives kernel WireGuard through netlink (embeddable-wg-library),
# owns an "inet" nftables table with ct/fib/masq/reject expressions and xt
# matches, splits traffic by cgroup (xt_cgroup, net_cls) and uses fwmark
# policy routing.
CONFIG_CHECK="
	~WIREGUARD
	~NF_TABLES
	~NF_TABLES_INET
	~NFT_CT
	~NFT_FIB_INET
	~NFT_MASQ
	~NFT_REJECT
	~NFT_COMPAT
	~NETFILTER_XT_MATCH_CGROUP
	~IP_MULTIPLE_TABLES
	~IPV6_MULTIPLE_TABLES
"

python_check_deps() {
	python_has_version "dev-python/pyyaml[${PYTHON_USEDEP}]"
}

pkg_setup() {
	linux-info_pkg_setup
	python-any-r1_pkg_setup
	rust_pkg_setup
}

src_unpack() {
	unpack ${P}-sources.tar.gz

	local orig=( "${WORKDIR}"/mozillavpn_"${PV}"*.orig.tar.gz )
	if [[ ${#orig[@]} -ne 1 || ! -f ${orig[0]} ]]; then
		die "expected exactly one mozillavpn_${PV}*.orig.tar.gz, found: ${orig[*]}"
	fi
	unpack "./${orig[0]##*/}"

	local src=( "${WORKDIR}"/mozillavpn-"${PV}"*/ )
	if [[ ${#src[@]} -ne 1 || ! -d ${src[0]} ]]; then
		die "expected exactly one mozillavpn-${PV}* source directory, found: ${src[*]}"
	fi
	mv "${src[0]%/}" "${S}" || die

	# The wrapper also carries a source RPM and the Debian source package;
	# none of it is used past this point. Every plain file in WORKDIR came
	# from the wrapper (a mozillavpn-${PV}* glob would also catch ${S}).
	find "${WORKDIR}" -maxdepth 1 -type f -delete || die
}

src_prepare() {
	cmake_src_prepare

	# The source release's .cargo/config.toml redirects crates.io to
	# 3rdparty/cargo-vendor, but not the one git dependency (udp-over-tcp,
	# pulled by the obfuscators crate), although `cargo vendor` did copy it
	# there. Without this entry cargo tries to clone it and the offline build
	# fails.
	local rev
	rev=$(sed -n 's|^source = "git+https://github.com/mullvad/udp-over-tcp?rev=\([0-9a-f]*\)#.*|\1|p' \
		Cargo.lock) || die
	[[ ${rev} =~ ^[0-9a-f]{40}$ ]] ||
		die "udp-over-tcp git revision not found in Cargo.lock; recheck the git sources"
	[[ -d 3rdparty/cargo-vendor/udp-over-tcp ]] || die "udp-over-tcp is not vendored"
	cat >> .cargo/config.toml <<-EOF || die

		[source."git+https://github.com/mullvad/udp-over-tcp?rev=${rev}"]
		git = "https://github.com/mullvad/udp-over-tcp"
		rev = "${rev}"
		replace-with = "vendored-sources"
	EOF
}

src_configure() {
	go-env_set_compile_environment
	# The netfilter c-archive is built with -mod vendor; never let go reach
	# for a newer toolchain or a module proxy.
	export GOTOOLCHAIN=local GOPROXY=off
	export CARGO_NET_OFFLINE=true

	local mycmakeargs=(
		-DBUILD_ID="${PV}"
		-DBUILD_TESTS=OFF
		# Sentry crash reporting: bundled sentry-native + breakpad, and a
		# crash report is sent to Mozilla.
		-DBUILD_CRASHREPORTING=OFF
		-DBUILD_FLATPAK=OFF
		-DBUILD_APPARMOR=OFF
		-DPYTHON_EXECUTABLE="${PYTHON}"
		# Firefox looks for system native messaging manifests here (the
		# RPM spec uses the same path); the default would be /usr/lib64.
		-DWEBEXT_INSTALL_LIBDIR="${EPREFIX}/usr/lib"
	)
	cmake_src_configure
}

src_install() {
	cmake_src_install

	# CMake installs both units into whatever pkg-config reports for systemd,
	# or into /lib/systemd/system if there is none. Take them back out and
	# install them only with USE=systemd; the OpenRC scripts below are
	# installed unconditionally.
	local unitdir
	for unitdir in "${ED}"/lib/systemd "${ED}"/usr/lib/systemd; do
		if [[ -d ${unitdir} ]]; then
			rm -r "${unitdir}" || die
		fi
	done
	if [[ -d ${ED}/lib ]]; then
		rmdir "${ED}"/lib || die "unexpected files left in /lib"
	fi

	newinitd "${FILESDIR}"/mozillavpn.initd mozillavpn
	newinitd "${FILESDIR}"/mozillavpn-socksproxy.initd mozillavpn-socksproxy
	if use systemd; then
		systemd_dounit "${BUILD_DIR}"/src/mozillavpn.service
		systemd_dounit "${BUILD_DIR}"/extension/socks5proxy/bin/socksproxy.service
	fi

	# Upstream installs its polkit rule only on Debian and Red Hat. Gentoo
	# takes the non-Debian one: local, active members of wheel may
	# (de)activate the VPN without a password prompt.
	insinto /usr/share/polkit-1/rules.d
	newins linux/org.mozilla.vpn.rules-others org.mozilla.vpn.rules

	dodoc README.md
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "The client drives a root daemon (mozillavpn linuxdaemon) over the system"
	elog "D-Bus. dbus-daemon starts it on demand, with or without systemd; to keep"
	elog "it running from boot instead, use one of:"
	elog "    rc-update add mozillavpn default"
	elog "    systemctl enable mozillavpn.service"
	elog
	elog "The browser extension's SOCKS proxy is a separate service:"
	elog "    rc-service mozillavpn-socksproxy start   (socksproxy.service on systemd)"
	elog
	elog "DNS: the daemon sets the tunnel's resolvers only through systemd-resolved"
	elog "(org.freedesktop.resolve1). Without it the tunnel still comes up, but"
	elog "/etc/resolv.conf is left untouched, so DNS keeps using the old servers."
	elog
	elog "Members of the wheel group may connect without a password prompt"
	elog "(/usr/share/polkit-1/rules.d/org.mozilla.vpn.rules)."
}
