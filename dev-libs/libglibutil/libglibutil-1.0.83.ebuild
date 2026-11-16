# Copyright 2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

DESCRIPTION="Library of GLib utilities from the Sailfish OS project"
HOMEPAGE="https://github.com/sailfishos/libglibutil"
SRC_URI="https://github.com/sailfishos/${PN}/archive/${PV}.tar.gz -> ${P}.tar.gz"

LICENSE="BSD"
SLOT="0"
KEYWORDS="~amd64"

DEPEND="dev-libs/glib:2"
RDEPEND="${DEPEND}"
BDEPEND="virtual/pkgconfig"

PATCHES=(
	# Drop the hardcoded -g/-O2 so CFLAGS from make.conf are honoured
	"${FILESDIR}"/${PN}-1.0.82-respect-env.patch
)

src_configure() {
	tc-export AR CC PKG_CONFIG STRIP
	# Portage strips; the Makefile must not do it behind its back
	export KEEP_SYMBOLS=1
	export LIBDIR="${EPREFIX}/usr/$(get_libdir)"
}

src_compile() {
	emake release pkgconfig
}

src_install() {
	emake DESTDIR="${D}" \
		INSTALL_INCLUDE_DIR="${ED}"/usr/include/gutil \
		install-dev
	einstalldocs
}
