# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-mod-r1

MY_PN="mediatek-mt7927-dkms"
MY_PV="${PV}-1"
MY_P="${MY_PN}-${MY_PV}"

# Kernel release whose mt76/bluetooth source the patches target. The mini source
# tarball carries only those subtrees (paths preserved); compat headers/shims
# cover 6.17 .. 7.1.
MT76_KVER="7.0"
KSRC_P="mt7927-kernel-src-${MT76_KVER}"
# Pre-extracted MT6639 WiFi + Bluetooth firmware blobs (proprietary, from the
# ASUS driver package).
FW_P="mt7927-firmware-${PV}"

# Base URL of the R2 bucket hosting the two repackaged distfiles above.
R2_BASE="https://distfiles.obentoo.org/DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R"

DESCRIPTION="Out-of-tree WiFi (mt7925e) + Bluetooth (btusb/btmtk) for MediaTek MT7927"
HOMEPAGE="https://github.com/jetm/mediatek-mt7927-dkms"
SRC_URI="
	https://github.com/jetm/${MY_PN}/archive/refs/tags/v${MY_PV}.tar.gz -> ${P}.tar.gz
	${R2_BASE}/${KSRC_P}.tar.xz
	${R2_BASE}/${FW_P}.tar.xz
"
S="${WORKDIR}/${MY_P}"

# Kernel modules + mini source are GPL-2; the MT6639 firmware blobs are
# proprietary MediaTek/ASUS with no redistribution grant.
LICENSE="GPL-2 all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"
# Do not let Gentoo mirrors carry the proprietary firmware.
RESTRICT="mirror"

# mt76 WiFi modules link against mac80211/cfg80211; the BT side needs the
# bluetooth core plus the btusb stack.
CONFIG_CHECK="~MAC80211 ~CFG80211 ~BT ~BT_HCIBTUSB"
# Upstream targets kernels 6.17+ (older lack the compat shims here).
MODULES_KERNEL_MIN="6.17"

# This package ships BOTH the WiFi side (mt7925e + mt76 stack) and the MT6639
# Bluetooth side (patched btusb/btmtk). The in-tree btusb/btmtk bind the BT USB
# interface (13d3:3588) as an MT7925 device and fail to reset it
# ("hci0: Opcode 0x0c03 failed: -16"); the upstream patches retarget it as the
# MT6639 (0x6639) variant, filter the firmware sections (only the 5 BT sections
# of 9 are sent to the chip) and load BT_RAM_CODE_MT6639, which neither the
# in-tree driver nor linux-firmware provide yet.

src_unpack() {
	unpack "${P}.tar.gz"
	unpack "${FW_P}.tar.xz"
}

src_prepare() {
	default

	local build="${WORKDIR}/_build"
	mkdir -p "${build}/mt76" "${build}/bt" || die

	# Extract the mt76 (WiFi) and bluetooth subtrees from the kernel mini source.
	tar -xf "${DISTDIR}/${KSRC_P}.tar.xz" --strip-components=6 \
		-C "${build}/mt76" \
		"linux-${MT76_KVER}/drivers/net/wireless/mediatek/mt76" || die
	tar -xf "${DISTDIR}/${KSRC_P}.tar.xz" --strip-components=3 \
		-C "${build}/bt" \
		"linux-${MT76_KVER}/drivers/bluetooth" || die

	# Apply the upstream MT7927 WiFi patch series (same order as upstream).
	pushd "${build}/mt76" >/dev/null || die
	eapply "${S}/mt7902-wifi-6.19.patch"
	eapply "${S}"/mt7927-wifi-*.patch
	# Kernel 7.1 flattened struct ieee80211_mgmt's per-action union and turned
	# IEEE80211_MIN_ACTION_SIZE into a function-like macro; the 7.0 mini source
	# predates that, so guard the ADDBA action parsing on LINUX_VERSION_CODE.
	eapply "${FILESDIR}/mt76-ieee80211-mgmt-action-7.1.patch"
	popd >/dev/null || die

	# Apply the MT6639 Bluetooth patch series: numbered patches (core support,
	# ISO interface fix, per-board USB IDs incl. 13d3:3588) plus the
	# version-guarded compat shim -- same set, same order as the jetm Makefile.
	pushd "${build}/bt" >/dev/null || die
	eapply "${S}"/mt6639-bt-[0-9]*.patch
	eapply "${S}"/mt6639-bt-compat-*.patch
	popd >/dev/null || die

	# Drop in the Kbuild/Makefile files and compat header (replaces `make sources`).
	cp "${S}/mt76.Kbuild"        "${build}/mt76/Kbuild" || die
	cp "${S}/mt7921.Kbuild"      "${build}/mt76/mt7921/Kbuild" || die
	cp "${S}/mt7925.Kbuild"      "${build}/mt76/mt7925/Kbuild" || die
	cp "${S}/bluetooth.Makefile" "${build}/bt/Makefile" || die
	mkdir -p "${build}/mt76/compat/include/linux/soc/airoha" || die
	cp "${S}/compat-airoha-offload.h" \
		"${build}/mt76/compat/include/linux/soc/airoha/airoha_offload.h" || die
}

src_compile() {
	local build="${WORKDIR}/_build"

	# WiFi: one `make M=.../mt76 modules` builds mt76, mt76-connac-lib,
	# mt792x-lib and recurses into mt7921/ and mt7925/.
	local wifi_dir="${build}/mt76"
	local modargs=( -C "${KV_OUT_DIR}" M="${wifi_dir}" )
	local modlist=(
		mt76=updates:"${wifi_dir}":"${wifi_dir}":modules
		mt76-connac-lib=updates:"${wifi_dir}":"${wifi_dir}":modules
		mt792x-lib=updates:"${wifi_dir}":"${wifi_dir}":modules
		mt7921-common=updates:"${wifi_dir}":"${wifi_dir}/mt7921":modules
		mt7921e=updates:"${wifi_dir}":"${wifi_dir}/mt7921":modules
		mt7925-common=updates:"${wifi_dir}":"${wifi_dir}/mt7925":modules
		mt7925e=updates:"${wifi_dir}":"${wifi_dir}/mt7925":modules
	)
	linux-mod-r1_src_compile

	# Bluetooth: patched btusb + btmtk (obj-m += btusb.o btmtk.o) retarget the
	# MT6639 BT USB interface. btintel/btbcm/btrtl symbols resolve against the
	# in-tree Module.symvers; btmtk is rebuilt here alongside btusb.
	local bt_dir="${build}/bt"
	modargs=( -C "${KV_OUT_DIR}" M="${bt_dir}" )
	modlist=(
		btmtk=updates:"${bt_dir}":"${bt_dir}":modules
		btusb=updates:"${bt_dir}":"${bt_dir}":modules
	)
	linux-mod-r1_src_compile
}

src_install() {
	linux-mod-r1_src_install

	# WiFi + Bluetooth firmware blobs.
	insinto /lib/firmware/mediatek/mt7927
	doins "${WORKDIR}/${FW_P}"/WIFI_*.bin
	doins "${WORKDIR}/${FW_P}"/BT_RAM_CODE_MT6639_*.bin

	# Force the out-of-tree updates/ modules to override the in-tree copies.
	local mod depmod_conf="${T}/${PN}.conf"
	{
		echo "# Generated by ${CATEGORY}/${PF}: prefer out-of-tree MT7927 modules"
		for mod in mt76 mt76-connac-lib mt792x-lib mt7921-common mt7921e \
			mt7925-common mt7925e btmtk btusb
		do
			echo "override ${mod} * updates"
		done
	} > "${depmod_conf}" || die
	insinto /lib/depmod.d
	doins "${depmod_conf}"
}

pkg_postinst() {
	linux-mod-r1_pkg_postinst

	elog "MediaTek MT7927 (Filogic 380) WiFi 7 + Bluetooth 5.4 driver installed."
	elog "  WiFi:      PCI 14c3:6639 (mt7925e)"
	elog "  Bluetooth: USB 13d3:3588 (btusb/btmtk, MT6639 variant, BT 5.4 / LE Audio)"
	elog ""
	elog "To activate without rebooting:"
	elog "    modprobe -r mt7925e mt7921e && modprobe mt7925e"
	elog "    modprobe -r btusb && modprobe btusb"
	elog ""
	elog "IMPORTANT (MT6639 BT firmware lock-up):"
	elog "If Bluetooth fails with 'hci0: Opcode 0x0c03 failed: -16', the BT"
	elog "firmware is locked and a normal reboot is NOT enough. Do a full power"
	elog "drain: shut down, switch off the PSU / unplug power, wait 10 seconds,"
	elog "then power back on. See jetm/mediatek-mt7927-dkms issue #23."
	elog ""
	elog "With USE=dist-kernel this is rebuilt automatically on kernel upgrades."
}
