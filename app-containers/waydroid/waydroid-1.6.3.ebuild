# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
PYTHON_REQ_USE="ssl"

inherit linux-info optfeature python-single-r1 systemd xdg

DESCRIPTION="Container-based approach to boot a full Android system on Linux"
HOMEPAGE="
	https://waydro.id
	https://github.com/waydroid/waydroid
"
SRC_URI="https://github.com/${PN}/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="apparmor +nftables systemd"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	app-containers/lxc[apparmor?,seccomp]
	net-dns/dnsmasq[dhcp]
	sys-apps/dbus
	sys-auth/polkit
	x11-libs/gtk+:3[introspection]
	x11-themes/hicolor-icon-theme
	$(python_gen_cond_dep '
		dev-python/dbus-python[${PYTHON_USEDEP}]
		>=dev-python/gbinder-1.3.0[${PYTHON_USEDEP}]
		dev-python/pygobject:3[${PYTHON_USEDEP}]
	')
	|| (
		media-video/pipewire[sound-server]
		media-sound/pulseaudio-daemon
	)
	nftables? ( net-firewall/nftables )
	!nftables? ( net-firewall/iptables )
"

pkg_setup() {
	# Binder is what Android talks through; netfilter backs waydroid-net.sh.
	# Warnings only: a distribution kernel may ship them as modules, and the
	# check cannot see a kernel that is built later.
	CONFIG_CHECK="
		~ANDROID_BINDER_IPC
		~ANDROID_BINDERFS
		~MEMFD_CREATE
		~PSI
		~!PSI_DEFAULT_DISABLED
		~BRIDGE
		~VETH
		~NETFILTER_XT_TARGET_MASQUERADE
		~NETFILTER_XT_NAT
	"
	if use nftables; then
		CONFIG_CHECK+="
			~NF_TABLES
			~NF_TABLES_INET
			~NFT_NAT
			~NFT_MASQ
		"
	else
		CONFIG_CHECK+="
			~IP_NF_IPTABLES
			~IP_NF_NAT
			~IP_NF_TARGET_MASQUERADE
			~NETFILTER_XT_TARGET_CHECKSUM
		"
	fi
	local ERROR_ANDROID_BINDER_IPC="CONFIG_ANDROID_BINDER_IPC is required: Android IPC runs over binder"
	local ERROR_ANDROID_BINDERFS="CONFIG_ANDROID_BINDERFS is required: waydroid allocates its binder nodes on binderfs"
	local ERROR_MEMFD_CREATE="CONFIG_MEMFD_CREATE is required: Android shared memory (ashmem) is emulated with memfd"
	local ERROR_PSI="CONFIG_PSI is required by the Android low-memory killer (lmkd)"

	linux-info_pkg_setup
	python-single-r1_pkg_setup
}

src_prepare() {
	default

	if ! use apparmor; then
		# lxc without AppArmor support refuses to start a container that
		# names a profile, even "unconfined" (waydroid#652)
		grep -q '^lxc\.apparmor\.profile =' data/configs/config_3 \
			|| die "apparmor line moved in config_3"
		sed -i '/^lxc\.apparmor\.profile =/d' data/configs/config_3 || die
	fi
}

src_compile() {
	:
}

src_install() {
	local mymakeargs=(
		DESTDIR="${D}"
		PREFIX="${EPREFIX}/usr"
		SYSCONFDIR="${EPREFIX}/etc"
		SYSD_DIR="$(systemd_get_systemunitdir)"
		USE_SYSTEMD=$(usex systemd 1 0)
		USE_NFTABLES=$(usex nftables 1 0)
		# The activation file hands off to the systemd unit
		# (SystemdService=); its Exec= fallback passes an option waydroid
		# 1.6.3 does not accept, so without systemd it can only fail.
		# There, the OpenRC service owns the bus name instead.
		USE_DBUS_ACTIVATION=$(usex systemd 1 0)
	)
	emake "${mymakeargs[@]}" install $(usev apparmor install_apparmor)

	if use nftables; then
		# The Makefile's sed exits 0 even when it matches nothing
		grep -q '^LXC_USE_NFT="true"' \
			"${ED}"/usr/lib/waydroid/data/scripts/waydroid-net.sh \
			|| die "USE_NFTABLES did not switch waydroid-net.sh to nftables"
	fi

	python_fix_shebang "${ED}"/usr/lib/waydroid/waydroid.py
	python_optimize "${ED}"/usr/lib/waydroid

	# Never USE-gated: the only way to run the container without systemd
	newinitd "${FILESDIR}"/waydroid-container.initd waydroid-container

	einstalldocs
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Waydroid needs an Android image before first use. Download it with"
	elog "  emerge --config ${CATEGORY}/${PN}"
	elog "or 'waydroid init' as root (add '-s GAPPS' for Google apps)."
	elog
	elog "Then start the container service:"
	elog "  OpenRC:  rc-service waydroid-container start"
	elog "           rc-update add waydroid-container default"
	if use systemd; then
		elog "  systemd: systemctl enable --now waydroid-container.service"
	fi
	elog "and, from a Wayland session as your user: 'waydroid session start'"
	elog "or 'waydroid show-full-ui'."
	elog
	elog "GPU acceleration in the container works through Mesa only (AMD, Intel,"
	elog "and other Mesa drivers). On NVIDIA proprietary drivers, switch the"
	elog "container to software rendering in /var/lib/waydroid/waydroid_base.prop:"
	elog "  ro.hardware.gralloc=default"
	elog "  ro.hardware.egl=swiftshader"
	elog "then restart the container. See https://docs.waydro.id/faq"
	if ! use nftables; then
		elog
		elog "USE=-nftables: waydroid-net.sh drives iptables (prefers iptables-legacy"
		elog "when present). Systems whose firewall is nftables want USE=nftables."
	fi
	if use apparmor; then
		elog
		elog "AppArmor profiles were installed under /etc/apparmor.d; load them with"
		elog "apparmor_parser or restart the apparmor service."
	fi

	optfeature "desktop notifications from Android apps" virtual/notification-daemon
	optfeature "shell completion of waydroid commands" dev-python/argcomplete
	elog
	elog "Clipboard sharing needs the 'pyclip' Python module, not packaged here;"
	elog "waydroid runs without it and only skips the clipboard service."
}

pkg_config() {
	"${EROOT}"/usr/bin/waydroid init || die "waydroid init failed"
}
