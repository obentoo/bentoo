# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit linux-mod-r1

MY_PN="mediatek-mt7927-dkms"
# Upstream re-tags the same version with an incrementing packaging revision
# (v2.14-1 ... v2.14-6) and the CONTENT differs between them: Makefile, the
# mt76/mt7925 Kbuilds and the shipped tree all change. So -N is NOT a mere
# packaging counter -- it must track upstream, which is why it lives in its own
# variable kept in sync by .autoupdate (aux_var), not hardcoded to -1.
MY_BUILD="2"
MY_PV="${PV}-${MY_BUILD}"
MY_P="${MY_PN}-${MY_PV}"

# Kernel release whose mt76/bluetooth source the patches target. The mini source
# tarball carries only those subtrees (paths preserved). Upstream 2.14 moved the
# base from 7.1.3 to 7.2, where Sean Wang's full MT7927 (Filogic 380) series
# landed in mainline: that is why the numbered WiFi patch set collapsed from 32
# to the 4 AP-mode additions still out of tree. Upstream 2.17 moved it again to
# 7.3 (new mt7925/nan.c); its patches do not apply to 7.2, so this MUST follow
# the PKGBUILD's _mt76_kver on every bump. The compat shims let the 7.3 code
# build against hosts from 6.17 up.
MT76_KVER="7.3"
KSRC_P="mt7927-kernel-src-${MT76_KVER}"
# Pre-extracted MT6639 Bluetooth firmware blob (proprietary, from the ASUS
# driver package V5603998_20250709R). The blob does not change with the dkms
# release, so pin the repackaged distfile version independently of ${PV}. It is
# fetched and installed UNCONDITIONALLY, including with USE=-btmtk: no other
# package on the system carries it (linux-firmware only takes vendor blobs from
# the copyright holder, so MR !946 was closed), and the kernel's OWN btmtk --
# the in-tree one that runs when this flag is off -- asks for the same file.
# Tying it to the flag left the native Bluetooth stack with no firmware at all.
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

# Kernel modules + mini source are GPL-2; the MT6639 firmware blob is
# proprietary MediaTek/ASUS with no redistribution grant.
LICENSE="GPL-2 all-rights-reserved"
SLOT="0"
KEYWORDS="~amd64"

# Kernel 7.1 gained native MT6639 Bluetooth, so from there the btusb/btmtk
# rebuild adds exactly one thing -- the HP EliteMini ID 0489:e156, which is not
# upstream -- while replacing the in-tree Bluetooth stack for every device on
# the machine. Upstream stopped building it by default in 2.14-6 for that
# reason; here it is a USE flag, off by default, so owners of an 0489:e156
# adapter opt in and nobody else pays for it. The ID has to appear in the
# driver's own btmtk_mt6639_devs[] table, so a `new_id` write is not a
# substitute for the module.
#
# The flag is named after the module, not "bluetooth": that one is a GLOBAL
# Gentoo USE flag enabled by most desktop profiles, so it would have turned this
# opt-in into an opt-out on exactly the systems that gain nothing from it.
IUSE="btmtk"

# Do not let Gentoo mirrors carry the proprietary firmware.
RESTRICT="mirror"

# mt76 WiFi modules link against mac80211/cfg80211; the BT side additionally
# needs the bluetooth core plus the btusb stack (checked in pkg_setup).
CONFIG_CHECK="~MAC80211 ~CFG80211"
# Upstream targets kernels 6.17+ (older lack the compat shims here).
MODULES_KERNEL_MIN="6.17"

pkg_setup() {
	use btmtk && CONFIG_CHECK+=" ~BT ~BT_HCIBTUSB"
	linux-mod-r1_pkg_setup
}

src_unpack() {
	unpack "${P}.tar.gz"
	unpack "${FW_P}.tar.xz"
}

src_prepare() {
	default

	local build="${WORKDIR}/_build"
	mkdir -p "${build}/mt76" || die

	# Extract the mt76 (WiFi) subtree from the kernel mini source.
	tar -xf "${DISTDIR}/${KSRC_P}.tar.xz" --strip-components=6 \
		-C "${build}/mt76" \
		"linux-${MT76_KVER}/drivers/net/wireless/mediatek/mt76" || die

	# Apply the upstream MT7927 WiFi patch series (same order as upstream's
	# `make sources` glob: the numbered 01..04 AP-mode additions first, then the
	# compat shims -- action frame, EML capability macros, kzalloc_flex, NAN and
	# regd/AQL. The last two are switched on by Kbuild probes of the host
	# headers, not by the kernel version).
	pushd "${build}/mt76" >/dev/null || die
	eapply "${S}"/mt7927-wifi-*.patch
	popd >/dev/null || die

	# Drop in the Kbuild files and compat header (replaces `make sources`).
	cp "${S}/mt76.Kbuild"        "${build}/mt76/Kbuild" || die
	cp "${S}/mt7921.Kbuild"      "${build}/mt76/mt7921/Kbuild" || die
	cp "${S}/mt7925.Kbuild"      "${build}/mt76/mt7925/Kbuild" || die
	mkdir -p "${build}/mt76/compat/include/linux/soc/airoha" || die
	cp "${S}/compat-airoha-offload.h" \
		"${build}/mt76/compat/include/linux/soc/airoha/airoha_offload.h" || die

	use btmtk || return 0

	mkdir -p "${build}/bt" || die
	tar -xf "${DISTDIR}/${KSRC_P}.tar.xz" --strip-components=3 \
		-C "${build}/bt" \
		"linux-${MT76_KVER}/drivers/bluetooth" || die

	# Apply the MT6639 Bluetooth patches: the numbered ones (the HP EliteMini
	# 0489:e156 ID missing from the 7.3 tables, no reset when the firmware is
	# absent), then every compat shim -- same set, same order as the jetm
	# Makefile. bt-local-version.h is not generated, so the module keeps the
	# in-tree MODULE_VERSION.
	pushd "${build}/bt" >/dev/null || die
	eapply "${S}"/mt6639-bt-[0-9]*.patch
	eapply "${S}"/mt6639-bt-compat-*.patch
	popd >/dev/null || die

	cp "${S}/bluetooth.Makefile" "${build}/bt/Makefile" || die
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

	use btmtk || return 0

	# Bluetooth: patched btusb + btmtk (obj-m += btusb.o btmtk.o) add the
	# 0489:e156 MT6639 ID. btintel/btbcm/btrtl symbols resolve against the
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

	# The MT7927 WiFi blobs are deliberately NOT installed. MediaTek's own build
	# reached sys-kernel/linux-firmware (MR !1055) as a .zst, and the kernel
	# firmware loader tries the uncompressed name first -- so a copy installed
	# here shadows the newer vendor blob with one extracted from a Windows
	# driver ZIP. Measured on this overlay: both packages owned files in
	# /lib/firmware/mediatek/mt7927 and the dkms .bin won. The Bluetooth blob is
	# still ours to ship: linux-firmware only takes vendor blobs from the
	# copyright holder, and MR !946 was closed on those grounds.
	local mod modules=(
		mt76 mt76-connac-lib mt792x-lib mt7921-common mt7921e
		mt7925-common mt7925e
	)

	# The MT6639 Bluetooth blob goes in either way. btmtk asks for
	# mediatek/mt7927/BT_RAM_CODE_MT6639_2_<n>_hdr.bin (hence the subdirectory),
	# and that is true of the IN-TREE btmtk as much as of the rebuilt one -- this
	# package is its only source anywhere on the system.
	insinto /lib/firmware/mediatek/mt7927
	doins "${WORKDIR}/${FW_P}"/BT_RAM_CODE_MT6639_*.bin

	use btmtk && modules+=( btmtk btusb )

	# Force the out-of-tree updates/ modules to override the in-tree copies.
	local depmod_conf="${T}/${PN}.conf"
	{
		echo "# Generated by ${CATEGORY}/${PF}: prefer out-of-tree MT7927 modules"
		for mod in "${modules[@]}"; do
			echo "override ${mod} * updates"
		done
	} > "${depmod_conf}" || die
	insinto /lib/depmod.d
	doins "${depmod_conf}"
}

pkg_postinst() {
	linux-mod-r1_pkg_postinst

	elog "MediaTek MT7927 (Filogic 380) WiFi 7 driver installed."
	elog "  WiFi: PCI 14c3:6639 (mt7925e)"
	elog ""
	elog "To activate without rebooting:"
	elog "    modprobe -r mt7925e mt7921e && modprobe mt7925e"
	elog ""

	# The WiFi firmware now has to come from linux-firmware. Removing the
	# bundled copy on a machine whose linux-firmware predates MR !1055 would
	# otherwise take out the very connection needed to fix it.
	local fw="${EROOT}/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin"
	if [[ ! -e ${fw} && ! -e ${fw}.zst && ! -e ${fw}.xz ]]; then
		ewarn "No MT7927 WiFi firmware found under /lib/firmware/mediatek/mt7927."
		ewarn "As of 2.14 this package no longer ships it -- the blob it used to"
		ewarn "install shadowed the newer one MediaTek upstreamed via linux-firmware"
		ewarn "MR !1055. Install or update sys-kernel/linux-firmware before"
		ewarn "rebooting, or the WiFi will not come up."
	fi

	if use btmtk; then
		elog "Bluetooth (USE=btmtk): USB 0489:e156 / 13d3:3588 (btusb/btmtk,"
		elog "MT6639 variant, BT 5.4 / LE Audio). This REPLACES the in-tree"
		elog "Bluetooth stack for every device on the system."
		elog ""
		elog "    modprobe -r btusb && modprobe btusb"
		elog ""
		elog "IMPORTANT (MT6639 BT firmware lock-up):"
		elog "If Bluetooth fails with 'hci0: Opcode 0x0c03 failed: -16', the BT"
		elog "firmware is locked and a normal reboot is NOT enough. Do a full power"
		elog "drain: shut down, switch off the PSU / unplug power, wait 10 seconds,"
		elog "then power back on. See jetm/mediatek-mt7927-dkms issue #23."
	else
		elog "Bluetooth modules were NOT built (USE=-btmtk), but the MT6639"
		elog "firmware WAS installed -- the kernel's own btmtk needs it and no"
		elog "other package ships it. Kernel 7.1 and newer carry native MT6639"
		elog "support, so the rebuild only adds the HP EliteMini ID 0489:e156,"
		elog "which is still not upstream. Enable USE=btmtk only if lsusb reports"
		elog "that exact ID -- the module is the only way to get it, since it"
		elog "must be in the driver's own btmtk_mt6639_devs[] table."
	fi
	elog ""
	elog "With USE=dist-kernel this is rebuilt automatically on kernel upgrades."
}
