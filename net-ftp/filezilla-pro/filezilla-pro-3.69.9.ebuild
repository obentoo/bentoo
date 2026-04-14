# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

WX_GTK_VER="3.2-gtk3"

inherit autotools wxwidgets xdg desktop

MY_PV="${PV/_/-}"
MY_P="FileZilla_Pro_${MY_PV}"

DESCRIPTION="Commercial verison of FileZilla"
HOMEPAGE="https://filezillapro.com/"
SRC_URI="https://distfiles.obentoo.org/${MY_P}_x86_64-linux-gnu.tar.xz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

# pugixml 1.7 minimal dependency is for c++11 proper configuration
RDEPEND="
	>=dev-libs/nettle-3.1:=
	>=dev-db/sqlite-3.7
	>=dev-libs/boost-1.76.0:=
	>=dev-libs/libfilezilla-0.50.0:=
	>=dev-libs/pugixml-1.7
	>=net-libs/gnutls-3.5.7
	x11-libs/wxGTK:${WX_GTK_VER}=[X]
	x11-misc/xdg-utils"
DEPEND="${RDEPEND}"

S="${WORKDIR}/FileZilla3"

pkg_nofetch() {
	einfo "Please download"
	#einfo "  - FileZilla_Pro_${PV}_x86_64-linux-gnu.tar.bz2"
	einfo "  - ${A}"
	einfo "from ${HOMEPAGE} and place it in your DISTDIR directory."
}

src_prepare() {
	default
	cd "${WORKDIR}/FileZilla3/share/applications/" || die
	mv filezilla.desktop filezilla-pro.desktop || die
	sed -i \
		-e 's/Exec=filezilla/Exec=filezilla-pro/' \
		-e 's/Icon=filezilla/Icon=filezilla-pro/' \
		filezilla-pro.desktop || die
}

src_install() {
	insinto /opt/${PN}
	doins -r * || die

	fperms +x "/opt/${PN}/bin/filezilla"
	dosym "/opt/${PN}/bin/filezilla" /usr/bin/filezilla-pro

	fperms +x "/opt/${PN}/bin/fzputtygen"
	dosym "/opt/${PN}/bin/fzputtygen" /usr/bin/fzputtygen-pro

	fperms +x "/opt/${PN}/bin/fzsftp"
	dosym "/opt/${PN}/bin/fzsftp" /usr/bin/fzsftp-pro

	fperms +x "/opt/${PN}/bin/fzstorj"
	dosym "/opt/${PN}/bin/fzstorj" /usr/bin/fzstorj-pro

	newicon share/pixmaps/filezilla.png filezilla-pro.png
	domenu share/applications/filezilla-pro.desktop
}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_mimeinfo_database_update
	xdg_icon_cache_update
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_mimeinfo_database_update
	xdg_icon_cache_update
}
