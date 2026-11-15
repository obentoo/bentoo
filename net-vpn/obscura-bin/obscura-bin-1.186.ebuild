# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop linux-info systemd unpacker xdg

DESCRIPTION="Obscura VPN client, service and desktop app (prebuilt binaries)"
HOMEPAGE="
	https://obscura.com/
	https://github.com/Sovereign-Engineering/obscuravpn-client
"

OBSCURA_POOL="https://linux-pkgs.obscura.com/deb/pool/main"
SRC_URI="
	${OBSCURA_POOL}/obscura-cli_${PV}_amd64.deb -> ${P}-cli-amd64.deb
	gui? ( ${OBSCURA_POOL}/obscura-gui_${PV}_amd64.deb -> ${P}-gui-amd64.deb )
"
S="${WORKDIR}"

# Up to 1.185 the debs shipped /usr/share/doc/obscura-{cli,gui}/copyright with
# the PolyForm Noncommercial 1.0.0 text, although upstream had relicensed the
# repository on 2026-09-22 (commit 3e55fb3fd6, "switch to GPLv3 License").
# The 1.186 debs finally say "GPL-3 with linking-source exception" (metainfo:
# GPL-3.0-only WITH GPL-3.0-linking-source-exception), so LICENSE follows them
# and matches net-vpn/obscura: the binaries link the same crates statically,
# and the GUI embeds the same web UI bundle.  Drop licenses/PolyForm-* once
# 1.185 leaves the tree.
LICENSE="GPL-3-with-openssl-exception"
# Statically linked crates (same set as net-vpn/obscura)
LICENSE+="
	Apache-2.0 Apache-2.0-with-LLVM-exceptions BSD-2 BSD
	CDLA-Permissive-2.0 GPL-3 ISC MIT MPL-2.0 openssl Unicode-3.0
	Unicode-DFS-2016 Unlicense ZLIB
"
# The embedded web UI bundle (same set as net-vpn/obscura)
LICENSE+=" gui? ( 0BSD Apache-2.0 BSD CC-BY-4.0 CC0-1.0 MIT OFL-1.1 )"
SLOT="0"
# amd64 only: the APT repository's Release file lists "Architectures: amd64"
# and there is no binary-arm64 index (checked 2026-09-24).  Upstream builds
# arm64 for no Linux package format, so there is nothing to keyword.
KEYWORDS="-* ~amd64"
IUSE="+gui systemd"
# No RESTRICT: GPL-3 allows mirroring and binary packages, which the
# PolyForm terms of 1.185 and older did not.  Stripping is allowed: the
# upstream ELFs carry full debug_info and nothing depends on it.

# NEEDED, from readelf -d on the 1.180 binaries:
#   obscura:     liblzma.so.5 libtss2-esys.so.0 libtss2-tctildr.so.0
#                libtss2-mu.so.0 libgcc_s.so.1 libm.so.6 libc.so.6
#   obscura-gui: libwebkitgtk-6.0.so.4 libjavascriptcoregtk-6.0.so.1
#                libgtk-4.so.1 libadwaita-1.so.0 libgio-2.0.so.0
#                libgobject-2.0.so.0 libglib-2.0.so.0 liblzma.so.5 + libc/gcc
# libtss2-tcti-device.so.0 (in the deb's Depends) is dlopen()ed by tctildr to
# reach /dev/tpmrm0; tpm2-tss always builds it.
# sys-apps/shadow: "obscura add-operator" runs usermod to add users to the
# obscura group.
RDEPEND="
	!net-vpn/obscura
	acct-group/obscura
	app-arch/xz-utils
	app-crypt/tpm2-tss
	sys-apps/shadow
	gui? (
		dev-libs/glib:2
		gui-libs/gtk:4
		gui-libs/libadwaita:1
		net-libs/webkit-gtk:6
	)
"
BDEPEND="app-arch/xz-utils"

QA_PREBUILT="usr/bin/obscura usr/bin/obscura-gui"

# The service creates a userspace tun device ("obscuravpn") and an
# "inet obscura" nftables table using conntrack marks plus an arp chain for
# its kill switch; without these it fails with NftablesSetup at startup.
CONFIG_CHECK="~TUN ~NF_TABLES ~NF_TABLES_INET ~NF_TABLES_ARP ~NFT_CT ~NF_CONNTRACK"

src_install() {
	dobin usr/bin/obscura

	# Always installed, never behind USE=systemd: the only way to run the
	# daemon on OpenRC.  Same content as net-vpn/obscura's pair.
	newinitd "${FILESDIR}"/obscura.initd obscura
	newconfd "${FILESDIR}"/obscura.confd obscura

	if use systemd; then
		systemd_dounit usr/lib/systemd/system/obscura.service
	fi
	# usr/lib/sysusers.d/obscura-cli.conf ("g obscura - -") is deliberately
	# not installed: acct-group/obscura creates the group on every init.

	if use gui; then
		dobin usr/bin/obscura-gui

		domenu usr/share/applications/net.obscura.vpn.gui.desktop

		insinto /usr/share/metainfo
		doins usr/share/metainfo/net.obscura.vpn.gui.metainfo.xml

		local size
		for size in 64 128 256; do
			doicon -s ${size} usr/share/icons/hicolor/${size}x${size}/apps/net.obscura.vpn.gui.png
		done
		# etc/apparmor.d/obscura-gui is an "unconfined" profile whose only
		# rule is "userns,": it exempts WebKit's sandbox from Ubuntu's
		# kernel.apparmor_restrict_unprivileged_userns=1 default.  That
		# sysctl is off unless an admin turns it on, so it is not installed.
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Start the service with one of:"
	elog "    rc-service obscura start && rc-update add obscura default"
	elog "    systemctl enable --now obscura.service"
	elog
	elog "Without systemd-resolved or NetworkManager the service refuses to"
	elog "start with --dns auto; see OBSCURA_DNS in /etc/conf.d/obscura."
	elog
	elog "Only members of the 'obscura' group may control the service:"
	elog "    obscura add-operator <user>    (then log in again)"
}
