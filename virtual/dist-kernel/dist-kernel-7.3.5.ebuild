# Copyright 2021-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# BENTOO-DIVERGENCE: RDEPEND - adds ~sys-kernel/bentoo-kernel{,-bin}-${PV}, so modules
# built against virtual/dist-kernel accept bentoo's kernel. Same PVR as the
# ::gentoo virtual on purpose: gentoo-kernel users still match the first
# alternative, and the subslot (0/${PVR}) stays the one they have installed.
# A revbump here would change it and rebuild every out-of-tree module
# (nvidia-drivers, virtualbox-modules, ...) for every bentoo user. This copy
# wins over ::gentoo's by repository priority (bentoo 0, gentoo -1000).
#
# Never prune the version matching the newest sys-kernel/bentoo-kernel, even
# when pkgcheck calls it RedundantVersion: bentoo-kernel pins the virtual to
# its own PV until a newer bentoo-kernel exists, so a bentoo-kernel machine
# resolves to exactly that version.

DESCRIPTION="Virtual to depend on any Distribution Kernel"
SLOT="0/${PVR}"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~loong ~m68k ~mips ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"

RDEPEND="
	|| (
		~sys-kernel/gentoo-kernel-${PV}
		~sys-kernel/gentoo-kernel-bin-${PV}
		~sys-kernel/vanilla-kernel-${PV%_p*}
		~sys-kernel/gentoo-kernel-modprep-${PV}
		~sys-kernel/bentoo-kernel-${PV}
		~sys-kernel/bentoo-kernel-bin-${PV}
	)
"
