# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

MY_P="lib${P}"

DESCRIPTION="GLib-style interface to Android binder"
HOMEPAGE="https://github.com/mer-hybris/libgbinder"
SRC_URI="https://github.com/mer-hybris/lib${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/${MY_P}"

LICENSE="BSD"
SLOT="0/${PV}"
KEYWORDS="~amd64"

DEPEND="
	dev-libs/glib:2
	dev-libs/libglibutil
"
RDEPEND="${DEPEND}"
BDEPEND="virtual/pkgconfig"

PATCHES=(
	# Use the system libglibutil, honour CFLAGS, RANLIB and STRIP
	"${FILESDIR}"/${PN}-1.1.52-respect-env.patch
)

src_configure() {
	tc-export AR CC PKG_CONFIG RANLIB STRIP
	# Portage strips; the Makefile must not do it behind its back
	export KEEP_SYMBOLS=1
	export LIBDIR="${EPREFIX}/usr/$(get_libdir)"
}

src_compile() {
	emake release pkgconfig
	emake -C tools release
}

src_install() {
	local -x DESTDIR="${D}"
	emake INSTALL_INCLUDE_DIR="${ED}"/usr/include/gbinder install-dev
	emake INSTALL_BIN_DIR="${ED}"/usr/bin -C tools install
	einstalldocs
}
