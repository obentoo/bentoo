# Copyright 2022-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# GNOME 51 mirror ahead of ::gentoo; drop each tag below when ::gentoo reaches this version
# BENTOO-DIVERGENCE: DEPEND - 1.10.0 bundles ministream instead of depending on appstream; glib/gtk floors raised
# BENTOO-DIVERGENCE: RDEPEND - 1.10.0 bundles ministream instead of depending on appstream

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )
inherit gnome.org meson python-any-r1 vala virtualx xdg

DESCRIPTION="Building blocks for modern GNOME applications"
HOMEPAGE="https://gnome.pages.gitlab.gnome.org/libadwaita/ https://gitlab.gnome.org/GNOME/libadwaita"

LICENSE="LGPL-2.1+"
SLOT="1"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"

IUSE="examples gtk-doc +introspection test +vala"
REQUIRED_USE="
	gtk-doc? ( introspection )
	vala? ( introspection )
"

RDEPEND="
	>=dev-libs/glib-2.89.3:2
	>=gui-libs/gtk-4.23.1:4[introspection?]
	dev-libs/fribidi
	introspection? ( >=dev-libs/gobject-introspection-1.83.2:= )
"
DEPEND="${RDEPEND}
"
BDEPEND="
	${PYTHON_DEPS}
	gtk-doc? ( >=dev-util/gi-docgen-2021.1 )
	vala? ( $(vala_depend) )
	dev-util/glib-utils
	sys-devel/gettext
	virtual/pkgconfig
	dev-lang/sassc
"

src_prepare() {
	default
	use vala && vala_setup
	xdg_environment_reset
}

src_configure() {
	local emesonargs=(
		# Never use gi-docgen subproject
		--wrap-mode nofallback
		# ministream is vendored in the tarball (subprojects/); no system package exists
		--force-fallback-for=ministream
		# ministream is vendored in the tarball (subprojects/), no system package exists
		--force-fallback-for=ministream

		-Dprofiling=false
		$(meson_feature introspection)
		$(meson_use vala vapi)
		$(meson_use gtk-doc documentation)
		$(meson_use test tests)
		$(meson_use examples)
	)
	meson_src_configure
}

src_test() {
	addwrite /dev/dri
	virtx meson_src_test --timeout-multiplier 2
}

src_install() {
	meson_src_install
	if use gtk-doc; then
		mkdir -p "${ED}"/usr/share/gtk-doc/html/ || die
		mv "${ED}"/usr/share/doc/${PN}-${SLOT} "${ED}"/usr/share/gtk-doc/html/ || die
	fi
}
