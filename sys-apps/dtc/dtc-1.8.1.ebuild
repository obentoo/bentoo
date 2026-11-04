# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 1.7.2-r2 ebuild, bumped to 1.8.1; python3_15 added.
# Both 1.7.2 patches (swig-4.3, glibc-2.41 execstack) are upstream. pylibfdt
# is now built by meson itself (py.extension_module, no setup.py), so the
# setuptools BDEPEND and SETUPTOOLS_SCM_PRETEND_VERSION are gone; meson now
# defaults to default_library=both, handled as in ::gentoo's 9999 ebuild.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added; setuptools dropped, 1.8 builds pylibfdt with meson.
# BENTOO-DIVERGENCE: PATCHES - swig-4.3 and glibc-2.41 execstack fixes are in 1.8.1.
PYTHON_COMPAT=( python3_{11..15} )
inherit dot-a meson python-single-r1

if [[ ${PV} == 9999 ]] ; then
	EGIT_REPO_URI="https://git.kernel.org/pub/scm/utils/dtc/dtc.git"
	inherit git-r3
else
	SRC_URI="https://www.kernel.org/pub/software/utils/${PN}/${P}.tar.xz"
	KEYWORDS="~amd64"
fi

DESCRIPTION="Open Firmware device tree compiler"
HOMEPAGE="https://devicetree.org/ https://git.kernel.org/cgit/utils/dtc/dtc.git/"

LICENSE="GPL-2"
SLOT="0"
IUSE="python static-libs test yaml"
RESTRICT="!test? ( test )"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

BDEPEND="
	app-alternatives/yacc
	app-alternatives/lex
	virtual/pkgconfig
	python? (
		${PYTHON_DEPS}
		dev-lang/swig
	)
"
RDEPEND="
	python? ( ${PYTHON_DEPS} )
	yaml? ( >=dev-libs/libyaml-0.2.3[static-libs?] )
"
DEPEND="
	${RDEPEND}
"

DOCS=(
	Documentation/dt-object-internal.txt
	Documentation/dts-format.txt
	Documentation/manual.txt
)

pkg_setup() {
	use python && python-single-r1_pkg_setup
}

src_configure() {
	use static-libs && lto-guarantee-fat
	local emesonargs=(
		-Ddefault_library=$(usex static-libs both shared)
		-Dtools=true
		-Dvalgrind=disabled # only used for some tests
		$(meson_feature python)
		$(meson_use test tests)
		$(meson_feature yaml)
	)

	meson_src_configure
}

src_install() {
	meson_src_install
	strip-lto-bytecode

	use python && python_optimize "${ED}"
}
