# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg

MY_PN="zed"
DESCRIPTION="The fast, collaborative code editor (binary package)"
HOMEPAGE="https://zed.dev https://github.com/zed-industries/zed"
SRC_URI="
	amd64? (
		https://github.com/zed-industries/zed/releases/download/v${PV}/${MY_PN}-linux-x86_64.tar.gz
			-> ${P}-linux-x86_64.tar.gz
	)
	arm64? (
		https://github.com/zed-industries/zed/releases/download/v${PV}/${MY_PN}-linux-aarch64.tar.gz
			-> ${P}-linux-aarch64.tar.gz
	)
"

S="${WORKDIR}/${MY_PN}.app"
LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
RESTRICT="mirror strip bindist"

RDEPEND="
	app-arch/zstd:=
	dev-db/sqlite:3
	>=dev-libs/libgit2-1.9.0:=
	dev-libs/openssl:0/3
	dev-libs/wayland
	|| (
		media-fonts/dejavu
		media-fonts/cantarell
		media-fonts/noto
		media-fonts/ubuntu-font-family
	)
	media-libs/alsa-lib
	media-libs/fontconfig
	media-libs/freetype
	media-libs/vulkan-loader[X]
"

QA_PREBUILT="
	opt/zed-bin/bin/*
	opt/zed-bin/libexec/*
	opt/zed-bin/lib/*
"

src_install() {
	# Install to /opt/zed-bin
	insinto /opt/zed-bin
	doins -r bin lib libexec
	dodoc licenses.md

	# Fix permissions for executables
	fperms +x /opt/zed-bin/libexec/zed-editor
	fperms +x /opt/zed-bin/bin/zed

	# Symlink CLI to /usr/bin as 'zedit' to avoid conflict with source ebuild
	dosym ../../opt/zed-bin/bin/zed /usr/bin/zedit-bin

	# Install icons
	if [[ -d share/icons ]]; then
		local size icon
		for icon in share/icons/hicolor/*/apps/zed.png; do
			if [[ -f "${icon}" ]]; then
				size="${icon#share/icons/hicolor/}"
				size="${size%%x*}"
				newicon -s "${size}" "${icon}" zed.png
			fi
		done
	fi

	# Install desktop file
	if [[ -f share/applications/zed.desktop ]]; then
		sed -e "s|^Exec=.*|Exec=/opt/zed-bin/bin/zed %U|" \
			-e "s|^Icon=.*|Icon=zed|" \
			share/applications/zed.desktop > "${T}/zed-bin.desktop" || die
		domenu "${T}/zed-bin.desktop"
	else
		make_desktop_entry "/opt/zed-bin/bin/zed %U" \
			"Zed (bin)" zed \
			"Development;IDE;TextEditor;" \
			"StartupNotify=true\nStartupWMClass=dev.zed.Zed\nMimeType=text/plain;inode/directory;"
	fi
}

pkg_postinst() {
	xdg_pkg_postinst

	elog "Zed binary edition installed."
	elog "Launch with: zedit-bin"
	elog ""
	elog "This package conflicts with app-editors/zed (source build)."
	elog "If you want the source-compiled version, use app-editors/zed instead."
}

pkg_postrm() {
	xdg_pkg_postrm
}
