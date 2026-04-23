# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{11..13} )

inherit meson python-any-r1 systemd

MY_COMMIT="5be2d11b1c4f74823fe9cb4d19945660b818563c"
LIBGLNX_COMMIT="ccea836b799256420788c463a638ded0636b1632"
GVDB_COMMIT="c6f2359cc1d00f16e0a0e2527fa0bc1882b8b5ab"

DESCRIPTION="Desktop integration portal"
HOMEPAGE="https://flatpak.github.io/xdg-desktop-portal/ https://github.com/flatpak/xdg-desktop-portal"
SRC_URI="
	https://github.com/flatpak/${PN}/archive/${MY_COMMIT}.tar.gz -> ${P}.tar.gz
	https://gitlab.gnome.org/GNOME/libglnx/-/archive/${LIBGLNX_COMMIT}/libglnx-${LIBGLNX_COMMIT}.tar.gz -> libglnx-${LIBGLNX_COMMIT}.tar.gz
	https://gitlab.gnome.org/GNOME/gvdb/-/archive/${GVDB_COMMIT}/gvdb-${GVDB_COMMIT}.tar.gz -> gvdb-${GVDB_COMMIT}.tar.gz
"

S="${WORKDIR}/${PN}-${MY_COMMIT}"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
IUSE="geolocation flatpak seccomp systemd test udev"
RESTRICT="!test? ( test )"
# Upstream expect flatpak to be used w/ seccomp and flatpak needs bwrap anyway
REQUIRED_USE="flatpak? ( seccomp )"

DEPEND="
	>=dev-libs/glib-2.76:2
	dev-libs/json-glib
	>=media-video/pipewire-0.3:=
	>=sys-fs/fuse-3.10.0:3=[suid]
	x11-libs/gdk-pixbuf
	geolocation? ( >=app-misc/geoclue-2.5.3:2.0 )
	flatpak? ( sys-apps/flatpak )
	seccomp? ( sys-apps/bubblewrap )
	systemd? ( sys-apps/systemd )
	udev? ( dev-libs/libgudev )
"
RDEPEND="
	${DEPEND}
	sys-apps/dbus
"
BDEPEND="
	>=dev-util/gdbus-codegen-2.80.5-r1
	dev-python/docutils
	sys-devel/gettext
	virtual/pkgconfig
	test? (
		${PYTHON_DEPS}
		dev-util/umockdev
		media-libs/gstreamer
		media-libs/gst-plugins-good
		$(python_gen_any_dep '
			>=dev-python/pytest-3[${PYTHON_USEDEP}]
			dev-python/pytest-xdist[${PYTHON_USEDEP}]
			dev-python/python-dbusmock[${PYTHON_USEDEP}]
		')
	)
"

pkg_setup() {
	use test && python-any-r1_pkg_setup
}

src_unpack() {
	default
	mv "${WORKDIR}/libglnx-${LIBGLNX_COMMIT}" "${S}/subprojects/libglnx" || die
	mv "${WORKDIR}/gvdb-${GVDB_COMMIT}" "${S}/subprojects/gvdb" || die
}

python_check_deps() {
	python_has_version ">=dev-python/pytest-3[${PYTHON_USEDEP}]" &&
	python_has_version "dev-python/pytest-xdist[${PYTHON_USEDEP}]" &&
	python_has_version "dev-python/python-dbusmock[${PYTHON_USEDEP}]"
}

src_configure() {
	# gst-plugin-scanner writes to /proc/self/task/*/comm for thread naming
	addpredict /proc/self/task
	# gst-plugin-scanner probes GPU render nodes when scanning VAAPI/NVDEC plugins
	addpredict /dev/dri

	local emesonargs=(
		-Ddbus-service-dir="${EPREFIX}/usr/share/dbus-1/services"
		-Dsystemd-user-unit-dir="$(systemd_get_userunitdir)"
		$(meson_feature flatpak flatpak-interfaces)
		$(meson_feature geolocation geoclue)
		$(meson_feature udev gudev)
		$(meson_feature seccomp sandboxed-image-validation)
		# Needs gstreamer-pbutils (part of gstreamer-rs)?
		# Not yet packaged
		#$(meson_feature seccomp sandboxed-sound-validation)
		-Dsandboxed-sound-validation=disabled
		$(meson_feature systemd)
		# Requires flatpak
		-Ddocumentation=disabled
		# -Dxmlto-flags=
		-Ddatarootdir="${EPREFIX}/usr/share"
		-Dman-pages=enabled
		-Dinstalled-tests=false
		$(meson_feature test tests)
	)

	meson_src_configure
}

src_install() {
	meson_src_install

	# Install a default to avoid breakage: >=1.18.0 assumes that DEs/WMs
	# will install their own, but we want some fallback in case they don't
	# (so will probably keep this forever). DEs need time to catch up even
	# if they will eventually provide one anyway. See bug #915356.
	#
	# TODO: Add some docs on wiki for users to add their own preference
	# for minimalist WMs etc.
	insinto /usr/share/xdg-desktop-portal
	newins "${FILESDIR}"/default-portals.conf portals.conf
	exeinto /etc/user/init.d
	newexe "${FILESDIR}"/xdg-desktop-portal.initd xdg-desktop-portal
}

pkg_postinst() {
	if ! has_version gui-libs/xdg-desktop-portal-lxqt && ! has_version gui-libs/xdg-desktop-portal-wlr && \
		! has_version kde-plasma/xdg-desktop-portal-kde && ! has_version sys-apps/xdg-desktop-portal-gnome && \
		! has_version sys-apps/xdg-desktop-portal-gtk && ! has_version sys-apps/xdg-desktop-portal-xapp; then
		elog "${PN} is not usable without any of the following XDP"
		elog "implementations installed:"
		elog "  gui-libs/xdg-desktop-portal-lxqt"
		elog "  gui-libs/xdg-desktop-portal-wlr"
		elog "  kde-plasma/xdg-desktop-portal-kde"
		elog "  sys-apps/xdg-desktop-portal-gnome"
		elog "  sys-apps/xdg-desktop-portal-gtk"
		elog "  sys-apps/xdg-desktop-portal-xapp"
	fi
}
