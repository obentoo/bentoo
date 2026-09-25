# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Plasma 6.8 beta 2, masked in profiles/package.mask. Copied from the Gentoo
# KDE team's overlay (github.com/gentoo/kde) with no change but these tags;
# each axis differs only because ::gentoo is still on the 6.7.x series.
# Drop this ebuild, tags included, once ::gentoo ships 6.8.0.
# BENTOO-DIVERGENCE: DEPEND - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: IUSE - upstream 6.8 beta, not in ::gentoo yet.
# BENTOO-DIVERGENCE: RDEPEND - upstream 6.8 beta, not in ::gentoo yet.

ECM_TEST=true
KFMIN=6.30.0
QTMIN=6.11.2
inherit ecm plasma.kde.org xdg

DESCRIPTION="Implementation of ssh-askpass with KDE Wallet integration"
HOMEPAGE+=" https://invent.kde.org/plasma/ksshaskpass"

LICENSE="GPL-2" # TODO: CHECK
SLOT="6"
KEYWORDS="~amd64 ~arm64 ~ppc64 ~riscv ~x86"
IUSE=""

DEPEND="
	>=dev-libs/qtkeychain-0.16.0:=
	>=dev-qt/qtbase-${QTMIN}:6[widgets]
	>=kde-frameworks/kconfig-${KFMIN}:6
	>=kde-frameworks/kcoreaddons-${KFMIN}:6
	>=kde-frameworks/ki18n-${KFMIN}:6
	>=kde-frameworks/kwallet-${KFMIN}:6
	>=kde-frameworks/kwidgetsaddons-${KFMIN}:6
"
RDEPEND="${DEPEND}"

src_install() {
	ecm_src_install

	insinto /etc/xdg/plasma-workspace/env/
	doins "${FILESDIR}/05-ksshaskpass.sh"
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "In order to have ssh-agent start with Plasma 6,"
	elog "edit /etc/xdg/plasma-workspace/env/10-agent-startup.sh"
	elog "and uncomment the lines enabling ssh-agent."
	elog
	elog "If you do so, do not forget to uncomment the respective"
	elog "lines in /etc/xdg/plasma-workspace/shutdown/10-agent-shutdown.sh"
	elog "to properly kill the agent when the session ends."
	elog
	elog "${PN} has been installed as your default askpass application"
	elog "for Plasma 6 sessions."
	elog "If that's not desired, select the one you want to use in"
	elog "/etc/xdg/plasma-workspace/env/05-ksshaskpass.sh"
}
