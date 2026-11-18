# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-info shell-completion systemd tmpfiles unpacker xdg

MY_PN="${PN%-bin}"

DESCRIPTION="NordVPN command-line client and daemon (prebuilt)"
HOMEPAGE="https://nordvpn.com/download/linux/
	https://github.com/NordSecurity/nordvpn-linux"
# The official APT repository, the one https://nordvpn.com/download/linux/
# installs.  GitHub releases of nordvpn-linux carry no assets.
SRC_URI="https://repo.nordvpn.com/deb/${MY_PN}/debian/pool/main/n/${MY_PN}/${MY_PN}_${PV}_amd64.deb
	-> ${P}-amd64.deb"
S="${WORKDIR}"

# Why the .deb and not a build from github.com/NordSecurity/nordvpn-linux:
# the public source only builds with FEATURES="telio drop".  "quench" (the
# NordWhisper obfuscation protocol) and "moose" (analytics) are internal builds
# whose repositories are not public, so a source build has no obfuscated
# connection at all -- and from 6.0 on NordWhisper is the only obfuscation.
#
# GPL-3: the CLI, the daemon, libtelio and libdrop.  all-rights-reserved:
# libquench and the two libmoose libraries, shipped only as binaries.
LICENSE="GPL-3 all-rights-reserved"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="systemd"
RESTRICT="bindist mirror strip"

# Libraries taken from readelf -d of every ELF in the 5.4.1 payload.  The
# Rust libraries link the unversioned libsqlite3.so, which dev-db/sqlite
# installs, so upstream's postinst symlink hack is not needed.  xsltproc
# renders the OpenVPN configuration from ovpn_template.xslt at connect time.
# The firewall goes through nf_tables over netlink (github.com/google/nftables),
# so no iptables/nft binary is required.
RDEPEND="
	acct-group/nordvpn
	app-misc/ca-certificates
	dev-db/sqlite:3
	dev-libs/libnl:3
	dev-libs/libxslt
	sys-apps/iproute2
	sys-libs/libcap-ng
	sys-process/procps
	systemd? ( sys-apps/systemd )
"

QA_PREBUILT="*"
# nordvpnd hardcodes /usr/lib/nordvpn for its helpers and libraries, so the
# 64-bit payload cannot move to /usr/lib64.
QA_MULTILIB_PATHS="usr/lib/nordvpn/.*"

CONFIG_CHECK="~TUN ~NF_TABLES ~WIREGUARD"
WARNING_WIREGUARD="CONFIG_WIREGUARD is needed for the NordLynx technology (the default)."

src_prepare() {
	default
	gunzip usr/share/man/man1/nordvpn.1.gz || die
}

src_install() {
	# The daemon resolves /usr/lib/nordvpn as its own directory, but the
	# binaries carry no RUNPATH: upstream writes /etc/ld.so.conf.d/nordvpn.conf
	# from postinst.  An env.d LDPATH is the Gentoo form of the same thing.
	insinto /usr/lib/nordvpn
	doins usr/lib/nordvpn/*.so
	exeinto /usr/lib/nordvpn
	doexe usr/lib/nordvpn/{nordfileshare,norduserd,openvpn}
	newenvd - 50${PN} <<-EOF
		LDPATH="/usr/lib/nordvpn"
	EOF

	dobin usr/bin/nordvpn
	dosbin usr/sbin/nordvpnd

	# Settings and the server list are rewritten by the daemon at runtime.
	insinto /var/lib/nordvpn/data
	doins var/lib/nordvpn/data/*
	fowners -R root:nordvpn /var/lib/nordvpn
	fperms 0750 /var/lib/nordvpn /var/lib/nordvpn/data
	keepdir /var/log/nordvpn
	fowners root:nordvpn /var/log/nordvpn
	fperms 0750 /var/log/nordvpn

	newinitd "${FILESDIR}"/nordvpnd.initd nordvpnd
	newconfd "${FILESDIR}"/nordvpnd.confd nordvpnd
	newinitd "${FILESDIR}"/nordvpnd-killswitch.initd nordvpnd-killswitch
	dotmpfiles usr/lib/tmpfiles.d/nordvpn.conf
	if use systemd; then
		# nordvpn.service in the payload is an empty file; skip it.
		systemd_dounit usr/lib/systemd/system/nordvpnd{,-killswitch}.service
		systemd_dounit usr/lib/systemd/system/nordvpnd.socket
	fi

	# Desktop entry: hidden, registers the nordvpn:// handler that completes
	# "nordvpn login" in the browser.
	insinto /usr/share
	doins -r usr/share/{applications,icons}

	dobashcomp usr/share/bash-completion/completions/nordvpn
	newzshcomp usr/share/zsh/functions/Completion/Unix/_nordvpn_auto_complete _nordvpn

	doman usr/share/man/man1/nordvpn.1
	dodoc usr/share/licenses/nordvpn/THIRD-PARTY-NOTICES.md
}

pkg_postinst() {
	xdg_pkg_postinst
	tmpfiles_process nordvpn.conf

	# 6.0 stores its settings in a new format and renames CLI commands
	# (whitelist -> allowlist, threatprotectionlite -> protection, protocol and
	# technology merged into "set protocol").  Announced by upstream on
	# 2026-10; the check fires on the first bump that crosses the boundary.
	local v
	for v in ${REPLACING_VERSIONS}; do
		if ver_test "${v}" -lt 6 && ver_test "${PV}" -ge 6; then
			ewarn "NordVPN ${PV} migrates its settings to a new format:"
			ewarn "downgrading back to ${v} loses them.  Several CLI commands were"
			ewarn "renamed (whitelist -> allowlist, threatprotectionlite -> protection,"
			ewarn "technology -> set protocol); update scripts, cron jobs and units."
			break
		fi
	done

	if [[ -z ${REPLACING_VERSIONS} ]]; then
		elog "Only members of the 'nordvpn' group can control the daemon:"
		elog "  usermod -aG nordvpn <user>   (then log in again)"
		elog
		elog "Start the daemon:"
		elog "  OpenRC:  rc-update add nordvpnd default && rc-service nordvpnd start"
		elog "           rc-update add nordvpnd-killswitch boot   (kill switch at boot)"
		elog "  systemd: systemctl enable --now nordvpnd.socket nordvpnd.service"
		elog "           systemctl enable nordvpnd-killswitch.service"
		elog
		elog "Then: nordvpn login && nordvpn connect"
	fi
}
