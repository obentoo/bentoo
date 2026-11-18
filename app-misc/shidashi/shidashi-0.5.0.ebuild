# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=hatchling
PYTHON_COMPAT=( python3_{14..15} )

inherit distutils-r1 tmpfiles

DESCRIPTION="Builds Bentoo (Gentoo stage5) images and live ISOs from a stage3"
HOMEPAGE="https://github.com/obentoo/shidashi"
SRC_URI="https://github.com/obentoo/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="MIT"
SLOT="0"
# amd64 only: Shidashi runs amd64 stage3s in systemd-nspawn on the host itself
# and its arch axis is x86-64 only (v3, znver5, arrowlake), so an arm64 host
# cannot run a build -- upstream does not support it.
KEYWORDS="~amd64"
# The languages the release translates, as L10N names; po/ spells them with
# an underscore (pt_BR, zh_CN), as gettext does.
L10N_LOCALES=( es pt-BR ru zh-CN )
IUSE="vm ${L10N_LOCALES[*]/#/l10n_}"

# Always: systemd-nspawn runs every build stage (and systemd-ssh-proxy reaches
# the VM), gpg verifies the stage3 and the ::gentoo snapshot, git fetches the
# pinned overlays, openssl hashes the live user's password, binutils' objdump
# checks the image's ISA. OpenSSH (ssh, ssh-keygen) pairs a build worker,
# provisions one and relays `worker`, `vm --dev --worker` and `ci pool` to it;
# rsync carries the caches with `worker sync`. Neither needs the vm flag: the
# host drives a worker's VMs without booting any itself. Portage runs inside
# the containers, and the ISO tools (grub, xorriso, mtools, squashfs-tools)
# inside the toolbox stage -- none of them is needed on the host. `shidashi
# doctor` checks the same list.
# sys-apps/systemd is a hard dependency on purpose: nspawn has no standalone
# package, so a host without systemd (split-usr, musl profiles) cannot build.
RDEPEND="
	app-arch/tar
	app-crypt/gnupg
	dev-libs/openssl
	dev-python/pydantic[${PYTHON_USEDEP}]
	dev-python/pyyaml[${PYTHON_USEDEP}]
	dev-python/rich[${PYTHON_USEDEP}]
	dev-python/typer[${PYTHON_USEDEP}]
	dev-vcs/git
	net-misc/rsync
	sys-apps/systemd
	sys-devel/binutils
	virtual/openssh
	vm? (
		app-emulation/qemu
		app-emulation/virtiofsd
		dev-libs/libisoburn
		|| (
			sys-firmware/edk2-bin
			sys-firmware/edk2
		)
	)
"

# msgfmt compiles the catalogs of the enabled languages. Nothing at run
# time: Python's gettext reads the .mo files itself.
BDEPEND="
	l10n_es? ( sys-devel/gettext )
	l10n_pt-BR? ( sys-devel/gettext )
	l10n_ru? ( sys-devel/gettext )
	l10n_zh-CN? ( sys-devel/gettext )
"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

python_compile_all() {
	# Only the languages in L10N: shidashi looks them up under
	# ${EPREFIX}/usr/share/locale (sys.base_prefix) and falls back to English.
	local l po
	for l in "${L10N_LOCALES[@]}"; do
		use "l10n_${l}" || continue
		po=${l/-/_}
		mkdir -p "locale/${po}/LC_MESSAGES" || die
		msgfmt --check -o "locale/${po}/LC_MESSAGES/${PN}.mo" "po/${po}.po" ||
			die "msgfmt failed for po/${po}.po"
	done
}

python_install_all() {
	distutils-r1_python_install_all

	if [[ -d locale ]]; then
		insinto /usr/share
		doins -r locale
	fi

	# The recipes (variants/) and the pinned inputs (seeds/) are data, not
	# code: the wheel carries only the package. An installed Shidashi finds them
	# here by itself; a checkout keeps using its own, and SHIDASHI_VARIANTS_DIR
	# still points a curator at another tree.
	insinto /usr/share/${PN}
	doins -r variants seeds

	# The vsock CID lock directory root's boot tests and users' `vm test` and
	# `vm start` share: root must create it at boot, or a copy a user made first
	# is refused (README, "shidashi vm"). contrib/systemd-user's CI poller is
	# not installed: it runs a checkout through uv, not this package.
	dotmpfiles contrib/tmpfiles.d/${PN}.conf
}

pkg_postinst() {
	tmpfiles_process ${PN}.conf

	elog "Shidashi keeps its data in:"
	elog "  ${EROOT}/var/cache/shidashi     binhost, fork points, pins, distfiles"
	elog "  ${EROOT}/var/log/shidashi/runs  audit trails"
	elog "  ${EROOT}/var/tmp/shidashi       scratch (build rootfs, VM sessions)"
	elog "Run 'shidashi doctor' to check what this host provides."
}
