# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-mod-r1

MY_PN="mediatek-mt7927-dkms"
MY_PV="${PV}-1"
MY_P="${MY_PN}-${MY_PV}"

# Kernel release whose mt76/bluetooth source the patches target. The mini source
# tarball carries only those subtrees (paths preserved). Upstream 2.13 moved the
# base from 7.0 to 7.1.3; the version-guarded compat shims in the patch series
# let the 7.1.3 code build against hosts from 6.17 up to 7.2.
MT76_KVER="7.1.3"
KSRC_P="mt7927-kernel-src-${MT76_KVER}"
# Pre-extracted MT6639 WiFi + Bluetooth firmware blobs (proprietary, from the
# ASUS driver package V5603998_20250709R). The blobs do not change with the
# dkms release, so pin the repackaged distfile version independently of ${PV}.
FW_PV="2.11"
FW_P="mt7927-firmware-${FW_PV}"

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
# Bluetooth side (btusb/btmtk). Kernel 7.1 carries native MT6639 support plus
# the known MT6639/MT7927 USB IDs -- including 13d3:3588 -- so the retarget
# patch series this ebuild used to carry is gone as of upstream 2.13; only an
# ID addition (0489:e156) and the pre-7.0 build shims remain. The modules are
# still rebuilt out-of-tree because the 7.1.3 mt76 side carries the MT7927
# fixes, and BT_RAM_CODE_MT6639 is still absent from linux-firmware.

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

	# Apply the upstream MT7927 WiFi patch series (same order as upstream: the
	# numbered 01..32 patches first, then the version-guarded compat shims).
	# The glob also picks up mt7927-wifi-compat-action-frame-for-pre-7.1-kernels
	# and -kzalloc_flex-for-pre-7.0-kernels, which replace the local shim this
	# ebuild used to carry back when the mini source was still 7.0-based.
	pushd "${build}/mt76" >/dev/null || die
	eapply "${S}"/mt7927-wifi-*.patch
	popd >/dev/null || die

	# Apply the MT6639 Bluetooth patches: the numbered one adds the HP EliteMini
	# 0489:e156 ID missing from the 7.1 tables, then the version-guarded compat
	# shim (kmalloc_obj, hci_discovery_active) for pre-7.0 hosts -- same set,
	# same order as the jetm Makefile.
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
