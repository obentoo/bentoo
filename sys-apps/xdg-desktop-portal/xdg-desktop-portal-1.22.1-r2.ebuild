# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )

# BENTOO-DIVERGENCE: PATCHES - two, where ::gentoo carries three.
#
# optional-gstreamer is deliberately absent and must stay absent: it invents a
# gstreamer USE flag upstream does not have, and this ebuild takes the
# dependency unconditionally as upstream declares it (see DEPEND below).
#
# sandbox-disable-failing-tests IS carried, rebased onto 1.22.1 and renamed
# version-agnostic - see the PATCHES block below. It was recorded as "does not
# apply, open" on 2026-09-07 and resolved the same day: their two hunks were
# reduced to one, because the trailing-newline fix they also carry is already
# upstream here.
#
# fix-dbus-service-startup is ::gentoo's (bug 985834), carried as-is under a
# version-agnostic name so a bump does not orphan it; drop it once upstream
# PR 2027 lands.
inherit meson python-any-r1 systemd

DESCRIPTION="Desktop integration portal"
HOMEPAGE="https://flatpak.github.io/xdg-desktop-portal/ https://github.com/flatpak/xdg-desktop-portal"
SRC_URI="https://github.com/flatpak/${PN}/releases/download/${PV}/${P}.tar.xz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
# BENTOO-DIVERGENCE: IUSE - no gstreamer flag. That flag is not upstream's: it
# comes from ::gentoo's own 1.20.4-optional-gstreamer.patch, which this overlay
# does not carry. Here the dependency is what upstream makes it, unconditional -
# see media-libs/gst-plugins-base in DEPEND below.
#
# sys-apps/bubblewrap travels with it, and dropping the flag is exactly how it
# went missing. ::gentoo declares it TWICE -- once in that gstreamer? block and
# once in seccomp? -- so folding the block in unconditionally took the
# gst-plugins-base half and left the bwrap half behind, under a USE flag a user
# can turn off.
#
# It is not optional in practice. src/meson.build compiles the bwrap path into
# xdg-desktop-portal-validate-{icon,sound} as -DHELPER only `if bwrap.found()`,
# and both binaries are built and installed unconditionally. Without it the
# #ifdef HELPER vanishes and the validator runs validate_icon(fd) directly --
# still working, still installed, but parsing untrusted payloads with no
# sandbox at all. Nothing fails; the isolation is just gone.
#
# So it is declared unconditionally and the seccomp? copy is dropped as
# redundant rather than kept alongside.
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
	media-libs/gst-plugins-base:1.0
	sys-apps/bubblewrap
	geolocation? ( >=app-misc/geoclue-2.5.3:2.0 )
	flatpak? ( sys-apps/flatpak )
	systemd? ( sys-apps/systemd )
	udev? ( dev-libs/libgudev )
"
RDEPEND="
	${DEPEND}
	sys-apps/dbus
"
# bubblewrap again here: meson.build runs find_program('bwrap') on the build
# host, so the DEPEND copy alone only works when ROOT=/ (::gentoo does the same).
BDEPEND="
	>=dev-util/gdbus-codegen-2.80.5-r1
	dev-python/docutils
	sys-apps/bubblewrap
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

python_check_deps() {
	python_has_version ">=dev-python/pytest-3[${PYTHON_USEDEP}]" &&
	python_has_version "dev-python/pytest-xdist[${PYTHON_USEDEP}]" &&
	python_has_version "dev-python/python-dbusmock[${PYTHON_USEDEP}]"
}

PATCHES=(
	# ::gentoo's sandbox-disable-failing-tests, rebased onto 1.22.1. Their
	# trailing-newline hunk is already upstream here, so only the two
	# pytest_files removals remain: test_dynamiclauncher.py and
	# test_location.py want a pipewire connection, network access and
	# /dev/fuse, and a portage sandbox gives none of the three.
	"${FILESDIR}"/${PN}-skip-sandbox-hostile-tests.patch
	# Taken from ::gentoo (bug 985834); pending upstream:
	# https://github.com/flatpak/xdg-desktop-portal/pull/2027
	"${FILESDIR}"/${PN}-fix-dbus-service-startup.patch
)

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

src_test() {
	# TAKEN FROM ::gentoo, and it is a real failure mode rather than a style
	# preference. A unix socket path is capped at 108 bytes, of which dbus
	# uses at most 99, and the test suite opens its bus under $TMPDIR - which
	# during a build is PORTAGE_TMPDIR/portage/<category>/<PF>/temp. That is
	# 56 bytes here before dbus appends anything, and a longer PORTAGE_TMPDIR
	# or a longer PF pushes it over; the same shape as the sccache SUN_LEN
	# failure this overlay has already been bitten by.
	#
	# So the suite runs under a short TMPDIR of its own, which is removed
	# afterwards. nonfatal + an explicit die keeps the cleanup on the failure
	# path: a bare meson_src_test would abort before the rm.
	local -x TMPDIR="$(mktemp -d --tmpdir=/tmp ${PF}-XXX || die)"
	nonfatal meson_src_test
	local ret="${?}"
	rm -r "${TMPDIR}" || die
	if [[ "${ret}" != 0 ]]; then
		die "tests failed"
	fi
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
