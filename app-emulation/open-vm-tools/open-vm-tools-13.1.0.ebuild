# Copyright 2007-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit autotools linux-info pam systemd udev

# Upstream appends an opaque build counter to the tarball name; it moves with
# every release and is not derivable from PV.  It is a variable of its own so
# the autoupdate applier can substitute it (aux_var in packages.toml) -- inline
# in MY_P it would survive a PV bump and 404 at manifest time.
MY_BUILD="25218885"
MY_P="${P}-${MY_BUILD}"

# BENTOO-DIVERGENCE: files/content - open-vm-tools.initd gains a "use vgauthd"
# line. It follows from this overlay shipping a vgauthd init script at all,
# which ::gentoo does not. "use" rather than "need" on purpose: it degrades to a
# no-op when the service is absent, where "need" would fail the start for anyone
# building without USE=vgauth.
DESCRIPTION="Tools for VMware guests"
HOMEPAGE="https://github.com/vmware/open-vm-tools"
SRC_URI="https://github.com/vmware/open-vm-tools/releases/download/stable-${PV}/${MY_P}.tar.gz"
S="${WORKDIR}/${MY_P}"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64 ~arm64 ~x86"
IUSE="X +deploypkg +dnet doc +fuse gtkmm +icu multimon pam +resolutionkms selinux +ssl +vgauth"
# BENTOO-DIVERGENCE: REQUIRED_USE - ::gentoo has "vgauth? ( ssl )"; this adds
# pam to the same clause.  configure.ac hard-errors on "--enable-vgauth
# --without-pam" ("Cannot enable vgauth without PAM"), so USE="vgauth -pam"
# dies mid-configure instead of at dependency resolution -- bug #971859,
# reproduced on 13.1.0.  Both flags default to on, so this constrains nobody
# who does not opt out on purpose.  Drop it once ::gentoo carries the same
# constraint.
REQUIRED_USE="
	multimon? ( X )
	vgauth? ( pam ssl )"

RDEPEND="
	dev-libs/glib
	net-libs/libtirpc
	deploypkg? ( dev-libs/libmspack )
	fuse? ( sys-fs/fuse:3= )
	pam? ( sys-libs/pam )
	!pam? ( virtual/libcrypt:= )
	ssl? ( dev-libs/openssl:= )
	vgauth? (
		dev-libs/libxml2:=
		dev-libs/xmlsec:=
	)
	X? (
		x11-libs/gtk+:3[X]
		x11-libs/libSM
		x11-libs/libXcomposite
		x11-libs/libXext
		x11-libs/libXi
		x11-libs/libXrandr
		x11-libs/libXrender
		x11-libs/libXtst
		gtkmm? (
			dev-cpp/gtkmm:3.0
			dev-libs/libsigc++:2
		)
		multimon? ( x11-libs/libXinerama )
	)
	dnet? ( dev-libs/libdnet )
	icu? ( dev-libs/icu:= )
	resolutionkms? (
		virtual/libudev
		>=media-libs/mesa-25.2[-video_cards_vmware]
		x11-base/xorg-server[xorg]
		x11-libs/libdrm[-video_cards_vmware]
	)"
DEPEND="${RDEPEND}
	net-libs/rpcsvc-proto"
BDEPEND="
	dev-util/glib-utils
	virtual/pkgconfig
	doc? ( app-text/doxygen )"
RDEPEND+=" selinux? ( sec-policy/selinux-vmware )"

# BENTOO-DIVERGENCE: PATCHES - ::gentoo carries the first five; the json-c and
# xmlsec ones are overlay-only.  The json-c one reorders -I flags so this
# tree's own debug.h wins over
# json-c's, which otherwise breaks every LOG() in the dndcp plugin.  That is
# bug #956496, open since 2025-05-23 and reproduced here identically on
# ::gentoo's own 13.0.10-r1 -- it is not a 13.1.0 regression.  Drop it once
# ::gentoo or upstream fixes the include order.
PATCHES=(
	"${FILESDIR}"/${PN}-12.4.5-Werror.patch
	"${FILESDIR}"/${PN}-12.4.5-icu.patch
	"${FILESDIR}"/${PN}-13.0.10-glibc-2.43-c23.patch
	"${FILESDIR}"/${PN}-13.0.10-glib-with-glibc-2.43-c23.patch
	"${FILESDIR}"/${PN}-13.1.0-configure-bashism.patch
	# Deliberately version-agnostic: it only reorders -I flags in a
	# Makefile.am that upstream has not touched across releases, and the
	# autoupdate applier never renames files/ on a bump.
	"${FILESDIR}"/${PN}-json-c-debug-h.patch
	# xmlsec 1.3.13 dropped dl.h from app.h, which is all crypto.h pulls in
	# under XMLSEC_CRYPTO_DYNAMIC_LOADING, so VGAuthService fails with an
	# implicit xmlSecCryptoDLLoadLibrary.  dl.h guards its own declarations, so
	# including it is a no-op on older xmlsec.  Overlay-only: ::gentoo 13.0.10-r1
	# carries the same unpatched source.
	"${FILESDIR}"/${PN}-xmlsec-dl-h.patch
)

pkg_setup() {
	local CONFIG_CHECK="~VMWARE_BALLOON ~VMWARE_PVSCSI ~VMXNET3 ~VMWARE_VMCI ~VMWARE_VMCI_VSOCKETS ~FUSE_FS"
	use X && CONFIG_CHECK+=" ~DRM_VMWGFX"
	kernel_is -lt 5 5 || CONFIG_CHECK+=" ~X86_IOPL_IOPERM"
	linux-info_pkg_setup
}

src_prepare() {
	default
	eautoreconf
}

src_configure() {
	local myeconfargs=(
		--disable-glibc-check
		--disable-tests
		--without-root-privileges
		$(use_enable multimon)
		$(use_with X x)
		$(use_with X gtk3)
		$(use_with gtkmm gtkmm3)
		$(use_enable doc docs)
		$(use_enable resolutionkms)
		$(use_enable deploypkg)
		$(use_with pam)
		$(use_enable vgauth)
		$(use_with dnet)
		$(use_with icu)
		--with-udev-rules-dir="$(get_udevdir)"/rules.d
		$(use_with fuse fuse 3)
		# Disable it explicitly, we do not yet list the
		# containerinfo dependencies in the ebuild
		--disable-containerinfo
		# 13.1.0 dropped gtk2 and added gtk4, whose default is "auto":
		# with gtk4 installed configure would pick it over gtk3 and then
		# demand gtkmm-4.0, which nothing here depends on.  --with-gtk3
		# above already wins that tie-break, but say it outright rather
		# than rely on the ordering inside configure.ac.
		--without-gtk4
		# Possibly add a separate USE flag for the utility, or
		# merge it into resolutionkms
		--disable-vmwgfxctrl
	)
	# Avoid a bug in configure.ac
	use ssl || myeconfargs+=( --without-ssl )

	# Avoid relying on dnet-config script, which breaks cross-compiling. This
	# library has no pkg-config file.
	export CUSTOM_DNET_LIBS="-ldnet"

	econf "${myeconfargs[@]}"
}

src_install() {
	default
	find "${ED}" -name '*.la' -delete || die

	if use pam; then
		rm "${ED}"/etc/pam.d/vmtoolsd || die
		pamd_mimic_system vmtoolsd auth account
	fi

	newinitd "${FILESDIR}/open-vm-tools.initd" vmware-tools
	newconfd "${FILESDIR}/open-vm-tools.confd" vmware-tools

	if use vgauth; then
		systemd_newunit "${FILESDIR}"/vmtoolsd.vgauth.service vmtoolsd.service
		systemd_dounit "${FILESDIR}"/vgauthd.service
		# VGAuthService is a second daemon, so it needs its own init
		# script.  Unlike the unit it is not gated on USE=systemd: an
		# OpenRC host would otherwise have no way to start it at all.
		newinitd "${FILESDIR}"/vgauthd.initd vgauthd
	else
		systemd_dounit "${FILESDIR}"/vmtoolsd.service
	fi

	# vmhgfs-fuse is built only when fuse is enabled
	if use fuse; then
		# Make fstype = vmhgfs-fuse work in fstab
		dosym vmhgfs-fuse /usr/bin/mount.vmhgfs-fuse
	fi

	if use X; then
		fperms 4711 /usr/bin/vmware-user-suid-wrapper
		dobin scripts/common/vmware-xdg-detect-de
	fi
}

pkg_postinst() {
	udev_reload

	if has_version ">=media-libs/mesa-25.2" && has_version "x11-drivers/xf86-video-vmware"; then
		elog "You need to remove x11-drivers/xf86-video-vmware to use the modesetting video driver."
	fi
}

pkg_postrm() {
	udev_reload
}
