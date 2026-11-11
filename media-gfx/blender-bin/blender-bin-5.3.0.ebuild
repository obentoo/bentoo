# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop xdg-utils

# BENTOO-DIVERGENCE: metadata.xml - a <longdescription> saying why a prebuilt
# Blender exists beside the from-source one, an <upstream> block, and USE flag
# descriptions rewritten to state what the flags actually do here (they keep or
# drop vendor libraries already inside the tarball; they build nothing).
# ::gentoo's file carries none of the first two. Added documentation, not drift;
# there is nothing to align back to. The maintainer block differs for the usual
# definitional reason and is suppressed by the parity sweep on its own.
DESCRIPTION="3D Creation/Animation/Publishing System"
HOMEPAGE="https://www.blender.org"

# ver_cut rather than ${SLOT}, even though the two are the same string: it keeps
# SRC_URI free of any ordering dependency on SLOT, so the variables can stay in
# the canonical order pkgcheck expects.
SRC_URI="
	https://download.blender.org/release/Blender$(ver_cut 1-2)/blender-${PV}-linux-x64.tar.xz
"

LICENSE="GPL-3+ Apache-2.0"
# One slot per major.minor series.  .blend files are not forward compatible and
# addons routinely pin a series, so several Blender versions have to coexist.
SLOT="$(ver_cut 1-2)"
# Upstream publishes a single Linux build, linux-x64.  There is no arm64
# tarball in any release directory, so ~arm64 here would name a file that does
# not exist -- verified across the whole release index, not just this series.
KEYWORDS="~amd64"

IUSE="cuda hip oneapi"
RESTRICT="strip test"

QA_PREBUILT="opt/${P}/*"

# no := here, this is prebuilt
RDEPEND="
	media-libs/libglvnd[X]
	sys-apps/util-linux
	sys-libs/glibc
	sys-libs/ncurses
	virtual/libcrypt
	x11-base/xorg-server
	x11-libs/libICE
	x11-libs/libSM
	x11-libs/libX11
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXi
	x11-libs/libXrender
	x11-libs/libXt
	x11-libs/libdrm
	x11-libs/libxkbcommon
	cuda? (
		x11-drivers/nvidia-drivers
	)
	hip? (
		=dev-util/hip-6*
	)
	oneapi? (
		dev-libs/level-zero
	)
"

src_unpack() {
	default

	# The tarball unpacks to blender-${PV}-linux-x64, not to ${P}.  Assert the
	# shape before moving: a second entry here means upstream changed the
	# archive layout, and the glob below would silently move the wrong thing.
	local dirs
	dirs="$(find "${WORKDIR}" -mindepth 1 -maxdepth 1 | wc -l)"
	if [[ "${dirs}" -ne 1 ]]; then
		die "unpack resulted in ${dirs} dirs in ${WORKDIR}"
	fi

	mv "${WORKDIR}"/* "${S}" || die "mv"
}

src_prepare() {
	default

	# Remove unused gpu libraries so we don't get missing libraries from QA
	if ! use cuda; then
		rm \
			lib/libOpenImageDenoise_device_cuda* \
			|| eqawarn "failed cleaning cuda"
	fi

	if ! use hip; then
		rm \
			lib/libOpenImageDenoise_device_hip* \
			|| eqawarn "failed cleaning hip"
	fi

	if ! use oneapi; then
		rm \
			lib/libOpenImageDenoise_device_sycl* \
			lib/libur_adapter_level_zero* \
			|| eqawarn "failed cleaning oneapi"
	fi

	# Prepare icons and .desktop for menu entry
	mv blender.desktop "${P}.desktop" || die
	mv blender.svg "${P}.svg" || die
	mv blender-symbolic.svg "${P}-symbolic.svg" || die

	sed \
		-e "s/=blender/=${P}/" \
		-e "s/Name=Blender/Name=Blender Bin ${PV}/" \
		-i "${P}.desktop" || die
}

src_configure() {
	:;
}

src_compile() {
	:;
}

src_install() {
	local BLENDER_OPT_HOME="/opt/${P}"

	# Install icons and .desktop for menu entry
	doicon -s scalable "${S}"/blender*.svg
	domenu "${P}.desktop"

	# Install all the blender files in /opt
	dodir "${BLENDER_OPT_HOME%/*}"
	mv "${S}" "${ED}${BLENDER_OPT_HOME}" || die

	# Create symlink /usr/bin/blender-bin
	dodir "/usr/bin"
	dosym -r "${BLENDER_OPT_HOME}/blender" "/usr/bin/${P}"
}

pkg_postinst() {
	xdg_icon_cache_update
	xdg_mimeinfo_database_update
	xdg_desktop_database_update
}

pkg_postrm() {
	xdg_icon_cache_update
	xdg_mimeinfo_database_update
	xdg_desktop_database_update
}
