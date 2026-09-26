# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit desktop pax-utils xdg

MY_PN="${PN%-bin}"

DESCRIPTION="OpenChamber, a cockpit for running parallel opencode sessions"
HOMEPAGE="https://github.com/OpenChamber/openchamber"
# AppImage is the only Linux artefact upstream publishes. unpacker.eclass has
# no AppImage support, so src_unpack peels the squashfs off by hand.
OC_BASE="https://github.com/OpenChamber/openchamber/releases/download/v${PV}"
SRC_URI="
	amd64? (
		${OC_BASE}/OpenChamber-${PV}-linux-x86_64.AppImage
			-> ${P}-amd64.AppImage
	)
	arm64? (
		${OC_BASE}/OpenChamber-${PV}-linux-arm64.AppImage
			-> ${P}-arm64.AppImage
	)
"
S="${WORKDIR}/${P}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="-* ~amd64 ~arm64"
IUSE="wayland"
RESTRICT="bindist mirror strip"

RDEPEND="
	>=app-accessibility/at-spi2-core-2.5.3
	>=dev-libs/expat-2.1_beta3
	>=dev-libs/glib-2.37.3:2
	>=dev-libs/nspr-4.9
	>=dev-libs/nss-3.26
	>=media-libs/alsa-lib-1.0.17
	>=media-libs/mesa-17.1.0[gbm(+)]
	>=sys-apps/dbus-1.9.14
	>=x11-libs/cairo-1.6.0
	>=x11-libs/gtk+-3.9.10:3[wayland?]
	>=x11-libs/libdrm-2.4.75
	>=x11-libs/libX11-1.4.99.1
	>=x11-libs/libXcomposite-0.4.4
	>=x11-libs/libXdamage-1.1
	x11-libs/libXext
	x11-libs/libXfixes
	x11-libs/libXrandr
	>=x11-libs/libxcb-1.9.2
	>=x11-libs/libxkbcommon-0.5.0
	x11-libs/libnotify
	>=x11-libs/pango-1.14.0
	>=x11-misc/xdg-utils-1.0.2
	wayland? ( dev-libs/wayland )
"

BDEPEND="
	sys-devel/binutils
	sys-fs/squashfs-tools
"

QA_PREBUILT="*"

src_unpack() {
	# An AppImage is an ELF launcher with a squashfs appended to it. The
	# filesystem starts right after the section header table, so the offset
	# is (e_shoff + e_shentsize * e_shnum) -- which is exactly what the
	# AppImage runtime's own --appimage-offset reports, obtained here without
	# executing the downloaded file.
	#
	# LC_ALL=C is not optional: readelf translates its field labels, and the
	# awk patterns below match the English ones.
	local hdr offset
	hdr=$(LC_ALL=C readelf -h "${DISTDIR}/${A}") || die "readelf failed"

	offset=$((
		$(awk '/Start of section headers/ {print $5}' <<<"${hdr}")
		+ $(awk '/Size of section headers/ {print $5}' <<<"${hdr}")
		* $(awk '/Number of section headers/ {print $5}' <<<"${hdr}")
	))
	[[ ${offset} -gt 0 ]] || die "could not compute the squashfs offset"

	unsquashfs -no-progress -o "${offset}" -d "${S}" "${DISTDIR}/${A}" ||
		die "failed to unpack the AppImage squashfs"
}

src_prepare() {
	default

	# The AppImage carries copies of system libraries so it can run on hosts
	# that lack them. None of them are in the binary's NEEDED list, and only
	# libnotify is referenced at all (dlopen'd for notifications), so they
	# are dropped in favour of the real packages in RDEPEND.
	#
	# Since 2.0.0 the icon at the root is a symlink into usr/, so it is
	# materialised first; otherwise doicon fails and /opt gets a dangling link.
	cp --remove-destination "usr/share/icons/hicolor/scalable/${MY_PN}.svg" \
		"${MY_PN}".svg || die
	rm -r usr || die

	# AppRun is the AppImage bootstrap and is meaningless once installed, as is
	# .DirIcon (the AppImage thumbnail, a link into the usr/ removed above).
	rm AppRun || die
	rm -f .DirIcon || die

	# Upstream's desktop entry launches "AppRun --no-sandbox". Both halves
	# are wrong here: AppRun is gone, and --no-sandbox is only there because
	# an AppImage cannot ship a setuid helper. This package installs
	# chrome-sandbox setuid, so the sandbox stays ON.
	sed -i -e "s|^Exec=AppRun --no-sandbox %U$|Exec=${MY_PN} %U|" \
		-e '/^X-AppImage-Version=/d' \
		"${MY_PN}".desktop || die

	grep -q "^Exec=${MY_PN} %U$" "${MY_PN}".desktop ||
		die "desktop Exec= was not rewritten; upstream entry may have changed"
	! grep -q -- '--no-sandbox' "${MY_PN}".desktop ||
		die "--no-sandbox survived in the desktop entry"
}

src_install() {
	local dest="/opt/${MY_PN}"

	dodir "${dest}"
	# cp -a rather than doins: the tree is a few thousand files whose
	# executable bits and symlinks matter, and doins would flatten them.
	cp -a . "${ED}${dest}"/ || die

	fperms 4755 "${dest}"/chrome-sandbox
	pax-mark m "${ED}${dest}/${MY_PN}"

	dosym -r "${dest}/${MY_PN}" /usr/bin/"${MY_PN}"

	domenu "${MY_PN}".desktop
	# 2.0.0 replaced the PNG icon with an SVG at the squashfs root.
	doicon -s scalable "${MY_PN}".svg
}
