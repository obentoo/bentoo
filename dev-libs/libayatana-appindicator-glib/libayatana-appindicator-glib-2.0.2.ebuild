# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake vala

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/AyatanaIndicators/${PN}.git"
	inherit git-r3
else
	SRC_URI="https://github.com/AyatanaIndicators/${PN}/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm64"
fi

DESCRIPTION="Ayatana Application Indicators (GLib-2.0-only reimplementation)"
HOMEPAGE="https://github.com/AyatanaIndicators/libayatana-appindicator-glib"

LICENSE="GPL-3"
SLOT="0"
IUSE="test"

RESTRICT="!test? ( test )"

DEPEND="dev-libs/glib:2"
RDEPEND="${DEPEND}"
# GObject introspection (GIR + typelib), the Vala vapi bindings and the
# gi-docgen documentation are all built unconditionally by upstream, so their
# generators are hard build dependencies. The FindGObjectIntrospection.cmake
# and FindVala.cmake modules are shipped by cmake-extras.
BDEPEND="
	$(vala_depend)
	dev-libs/gobject-introspection
	dev-util/cmake-extras
	dev-util/gi-docgen
	virtual/pkgconfig
	test? ( dev-util/dbus-test-runner )
"

src_configure() {
	vala_setup

	# cmake-extras' FindVala does a bare find_program(valac/vapigen); Gentoo
	# only ships versioned binaries, so feed it the paths vala_setup exported.
	local mycmakeargs=(
		-DENABLE_TESTS=$(usex test)
		-DENABLE_WERROR=OFF
		-DVALA_COMPILER="${VALAC}"
		-DVAPI_GEN="${VAPIGEN}"
	)
	cmake_src_configure
}
