# Copyright 1999-2018 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit unpacker xdg
DESCRIPTION="cross-platform Git client"
HOMEPAGE="https://www.gitkraken.com"
DL_HASH="38DozAgTFlmPZh5NXUXhhvYaNLN"
SRC_URI="https://release.gitkraken.dev/gkd/production/normal/linux/x64/${PV}/${DL_HASH}/gitkraken-amd64.deb -> GitKraken-v${PV}.deb"

SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip"

# USE flags
IUSE="gnome kde"

S="${WORKDIR}"

RDEPEND="
	>=net-print/cups-1.7.0
	>=x11-libs/cairo-1.6.0
	>=sys-libs/glibc-2.17
	>=media-libs/fontconfig-2.11
	media-sound/alsa-utils
	>=dev-libs/atk-2.5.3
	>=app-accessibility/at-spi2-atk-2.9.90
	>=sys-apps/dbus-1.9.14
	>=x11-libs/libdrm-2.4.38
	>=dev-libs/expat-2.0.1
	>=x11-libs/gtk+-3.9.10
	>=dev-libs/nss-3.22
	>=x11-libs/pango-1.14.0
	>=x11-libs/libX11-1.4.99.1
	>=x11-libs/libxcb-1.9.2
	>=x11-libs/libXcomposite-0.3
	>=x11-libs/libXdamage-1.1
	x11-libs/libXext
	x11-libs/libXfixes
	>=x11-libs/libxkbcommon-0.5.0
	x11-libs/libXrandr
	dev-libs/libgcrypt
	x11-libs/libnotify
	x11-libs/libXtst
	x11-libs/libxkbfile
	dev-libs/glib
	x11-misc/xdg-utils
	sys-fs/e2fsprogs
	>=dev-vcs/git-2.45.2
	app-crypt/mit-krb5
	net-misc/curl
	app-misc/trash-cli
	kde? (
		kde-plasma/kde-cli-tools
	)
	gnome? (
		gnome-base/gvfs
	)
"

PATCHES=(
	"${FILESDIR}/desktop-file.patch"
)

#TODO: ???
LICENSE="EULA"

QA_FLAGS_IGNORED=".*"
QA_PREBUILT="*"

S="${WORKDIR}"

src_install() {
	mv "${S}"/usr/share/doc/gitkraken "${S}"/usr/share/doc/"${PF}"

	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@axosoft/nodegit/build/Release/nodegit-ubuntu-18-ssl-1.0.0.node
	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@axosoft/nodegit/build/Release/nodegit-ubuntu-18-ssl-1.1.0.node
	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@axosoft/nodegit/build/Release/nodegit-ubuntu-18-ssl-10.node
	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@axosoft/nodegit/build/Release/nodegit-ubuntu-18.node
	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@axosoft/nodegit/build/Release/nodegit-ubuntu-20.node
	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@axosoft/nodegit/build/Release/nodegit.node

	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@msgpackr-extract/msgpackr-extract-linux-x64/node.napi.musl.node
	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@msgpackr-extract/msgpackr-extract-linux-x64/node.abi108.musl.node
	rm -rf "${S}"/usr/share/gitkraken/resources/app.asar.unpacked/node_modules/@msgpackr-extract/msgpackr-extract-linux-x64/node.abi115.musl.node

	mkdir "${S}"/opt

	mv "${S}"/usr/share/gitkraken "${S}"/opt

	rm -rf "${S}"/usr/share/gitkraken
	rm -rf "${S}"/usr/bin/

	cp -a "${S}"/* "${D}" || die "Installation failed"

	docompress -x usr/share/doc/"${PF}"/*.gz

	dosym /opt/gitkraken/gitkraken /usr/bin/gitkraken

	echo "SEARCH_DIRS_MASK=\"/opt/gitkraken\"" > "${T}"/70-"${PN}" || die
	insinto /etc/revdep-rebuild && doins "${T}"/70-"${PN}" || die
}

pkg_postinst() {
	xdg_desktop_database_update
}

pkg_postrm() {
	xdg_desktop_database_update
}
