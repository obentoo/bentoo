# Copyright 1999-2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit rpm xdg

MY_PV=$(ver_cut 1-3)

DESCRIPTION="Official Beta Proton Mail Linux app"
HOMEPAGE="https://proton.me https://github.com/ProtonMail/inbox-desktop"
SRC_URI="https://proton.me/download/mail/linux/${PV}/ProtonMail-desktop-beta.rpm -> ${P}.rpm"
S="${WORKDIR}"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64 ~x86"
IUSE="pulseaudio"

DEPEND="
	gui-libs/gtk
	x11-libs/libnotify
	dev-libs/nss
	media-libs/alsa-lib
	x11-misc/xdg-utils
        || (
		gnome-base/gvfs
		app-misc/trash-cli
		kde-plasma/kde-cli-tools
	)
	pulseaudio? (
		|| (
				media-libs/libpulse
				media-sound/apulse
		)
	)

"

RDEPEND="${DEPEND}"

QA_PREBUILT="opt/proton-mail/*"

src_install() {
	into /opt
	cp -r "${S}"/usr/lib/* "${D}"/opt/proton-mail || die "Failed to install!"
	dosym "/opt/proton-mail/Proton Mail Beta" "/usr/bin/proton-mail"
	insinto /usr/share
	doins -r "${S}/usr/share/pixmaps"
	doins -r "${S}/usr/share/applications"
}
