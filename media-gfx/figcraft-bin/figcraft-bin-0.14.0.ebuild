# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit optfeature xdg

MY_PN="${PN%-bin}"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Clean-room Figma-style interface design and prototyping tool (binary package)"
HOMEPAGE="https://github.com/storytold/figcraft"
SRC_URI="https://github.com/storytold/${MY_PN}/releases/download/v${PV}/${MY_P}-linux-x86_64.tar.gz"
S="${WORKDIR}/${MY_P}-linux-x86_64"

# Fonts compiled into the binary: egui's defaults (Ubuntu Light, Hack, Noto
# Emoji) and the suite's own OFL families.
LICENSE="|| ( Apache-2.0 MIT ) BitstreamVera OFL-1.1 UbuntuFontLicense-1.0"
# Dependent crate licenses, surveyed for 0.8.0 with `cargo tree -e normal
# --target x86_64-unknown-linux-gnu --format {l}` over the two shipped
# binaries. Only licenses that are not an "OR" alternative to one already
# listed are named. Redo the survey on every bump: the version moves, this
# list does not.
LICENSE+=" Apache-2.0 BSD BSD-2 CDLA-Permissive-2.0 ISC MIT MPL-2.0 OFL-1.1 UbuntuFontLicense-1.0 Unicode-3.0 ZLIB"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="strip"

# Both binaries link only glibc and libgcc_s; everything below is dlopen()ed
# at runtime (winit, wgpu, rfd), so no tool would derive it. The 0.8.0 GUI
# binary names the same libraries as its suite siblings (libvulkan, libEGL,
# libwayland-client/-egl, libxcb, libX11, libX11-xcb, libXcursor, libXi,
# libxkbcommon(-x11), libdbus-1); wgpu tries Vulkan first and falls back to
# EGL.
RDEPEND="
	dev-libs/wayland
	media-libs/libglvnd
	media-libs/vulkan-loader
	sys-apps/dbus
	x11-libs/libX11
	x11-libs/libxcb
	x11-libs/libXcursor
	x11-libs/libXi
	x11-libs/libxkbcommon[X]
"

QA_PREBUILT="usr/bin/${MY_PN} usr/bin/${MY_PN}-cli"

src_install() {
	dobin bin/${MY_PN} bin/${MY_PN}-cli
	dodoc share/doc/${MY_PN}/{NOTICE,README.md}

	# The doc tree went through dodoc; the font licence texts it also
	# carries are covered by LICENSE.
	rm -r share/doc || die
	insinto /usr/share
	doins -r share/.
}

pkg_postinst() {
	xdg_pkg_postinst

	# rfd asks org.freedesktop.portal.FileChooser first and runs zenity only
	# when no portal answers.
	optfeature "file dialogs without an XDG desktop portal" gnome-extra/zenity
}
