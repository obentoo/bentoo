# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

DESCRIPTION="cross-platform Git client"
HOMEPAGE="https://www.gitkraken.com"
SRC_URI="https://api.gitkraken.dev/releases/production/linux/x64/${PV}/gitkraken-amd64.tar.gz -> ${P}-linux-amd64.tar.gz"

SLOT="0"
KEYWORDS="~amd64"
RESTRICT="strip mirror"

# USE flags
IUSE="gnome kde"

S="${WORKDIR}/gitkraken"

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

#TODO: ???
LICENSE="EULA"

QA_FLAGS_IGNORED=".*"
QA_PREBUILT="*"

src_install() {
	insinto /opt/gitkraken
	doins -r .

	# Fix permissions for executables
	fperms +x /opt/gitkraken/gitkraken
	fperms +x /opt/gitkraken/chrome-sandbox
	fperms 4755 /opt/gitkraken/chrome-sandbox
	fperms +x /opt/gitkraken/chrome_crashpad_handler

	dosym ../../opt/gitkraken/gitkraken /usr/bin/gitkraken

	# Install icon
	if [[ -f gitkraken.png ]]; then
		doicon gitkraken.png
	fi

	# Install desktop file
	make_desktop_entry "/usr/bin/gitkraken %U" \
		"GitKraken" gitkraken \
		"Development;RevisionControl;" \
		"StartupNotify=true\nMimeType=x-scheme-handler/gitkraken;"

	echo "SEARCH_DIRS_MASK=\"/opt/gitkraken\"" > "${T}"/70-"${PN}" || die
	insinto /etc/revdep-rebuild && doins "${T}"/70-"${PN}" || die
}

pkg_postinst() {
	xdg_desktop_database_update
}

pkg_postrm() {
	xdg_desktop_database_update
}
