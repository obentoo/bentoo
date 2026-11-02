# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit optfeature xdg

MY_PN="${PN%-bin}"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Clean-room Lightroom-style photo library and raw developer (binary package)"
HOMEPAGE="https://github.com/storytold/lightcraft"
SRC_URI="https://github.com/storytold/${MY_PN}/releases/download/v${PV}/${MY_P}-linux-x86_64.tar.gz"
S="${WORKDIR}/${MY_P}-linux-x86_64"

# Fonts compiled into the binary: egui's defaults (Ubuntu Light, Hack, Noto
# Emoji) and the suite's own OFL families.
# Also bundled: camera colour matrices derived from the CIE 1931
# colour-matching functions (CC-BY-4.0).
LICENSE="|| ( Apache-2.0 MIT ) BitstreamVera OFL-1.1 UbuntuFontLicense-1.0 CC-BY-4.0"
# Dependent crate licenses, surveyed for 0.10.0 with `cargo tree -e normal
# --target x86_64-unknown-linux-gnu --format {l}` over the two shipped
# binaries. Only licenses that are not an "OR" alternative to one already
# listed are named. Redo the survey on every bump: the version moves, this
# list does not.
LICENSE+=" Apache-2.0 BSD BSD-2 CDLA-Permissive-2.0 IJG ISC MIT OFL-1.1 UbuntuFontLicense-1.0 Unicode-3.0 ZLIB"
SLOT="0"
KEYWORDS="-* ~amd64"
RESTRICT="strip"

# Both binaries link only glibc; everything below is dlopen()ed at
# runtime (winit, wgpu, rfd), so no tool would derive it. Measured with
# LD_DEBUG=files on 0.6.0, on both the X11 and the Wayland backend; wgpu
# tries Vulkan first and falls back to EGL.
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
	dodoc share/doc/${MY_PN}/{README.md,NOTICE}

	# The doc tree went through dodoc; the icons' provenance sidecars would
	# otherwise land inside the hicolor theme.
	rm -r share/doc || die
	find share -name '*.attribution' -delete || die
	insinto /usr/share
	doins -r share/.
}

pkg_postinst() {
	xdg_pkg_postinst

	# rfd asks org.freedesktop.portal.FileChooser first and runs zenity only
	# when no portal answers.
	optfeature "file dialogs without an XDG desktop portal" gnome-extra/zenity
}
