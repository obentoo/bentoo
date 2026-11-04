# Copyright 2004-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Based on ::gentoo's 20230101-r2 ebuild, bumped to 20251009; python3_15
# added. Upstream removed the Xlib GUI backend: the GUI is now GTK3 plus
# gtkmm-3.0 (C++17) only, so USE=X is gone and USE=gtk pulls dev-cpp/gtkmm.
# The new ENABLE_HARFBUZZ shaper is automagic upstream and is wired to
# USE=harfbuzz. The three 20230101 patches are upstream (PR #5367 shell
# injection, PR #5423 sysconfig instead of distutils, fixed fr.po format
# strings) and are dropped; libltdl is no longer referenced by the sources.
# BENTOO-DIVERGENCE: IUSE - python3_15 added; X dropped (Xlib backend removed upstream); harfbuzz added.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added; harfbuzz requires gtk (shaper is GUI-only).
# BENTOO-DIVERGENCE: DEPEND - python3_15 added; GUI is gtk+:3 + gtkmm:3.0, X11 libs and libltdl dropped.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added; GUI is gtk+:3 + gtkmm:3.0, X11 libs and libltdl dropped.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added; test? pulls the reworked RDEPEND.
# BENTOO-DIVERGENCE: PATCHES - the three 20230101 patches are upstream in 20251009.
# BENTOO-DIVERGENCE: KEYWORDS - bumped past ::gentoo, so overlay baseline ~amd64 only.
PYTHON_COMPAT=( python3_{11..15} )
inherit python-single-r1 xdg cmake

DESCRIPTION="postscript font editor and converter"
HOMEPAGE="https://fontforge.org/"
SRC_URI="https://github.com/fontforge/fontforge/releases/download/${PV}/${P}.tar.xz"

LICENSE="BSD GPL-3+"
SLOT="0"
KEYWORDS="~amd64"
IUSE="doc truetype-debugger gif gtk harfbuzz jpeg png +python readline test tiff svg woff2"
RESTRICT="!test? ( test )"
REQUIRED_USE="
	harfbuzz? ( gtk )
	python? ( ${PYTHON_REQUIRED_USE} )
"

RDEPEND="
	>=dev-libs/glib-2.67:2
	dev-libs/libxml2:2=
	>=media-libs/freetype-2.3.7:2=
	gif? ( media-libs/giflib:= )
	jpeg? ( media-libs/libjpeg-turbo:= )
	png? ( media-libs/libpng:= )
	tiff? ( media-libs/tiff:= )
	truetype-debugger? ( >=media-libs/freetype-2.3.8:2[fontforge,-bindist(-)] )
	gtk? (
		dev-cpp/gtkmm:3.0
		>=x11-libs/gtk+-3.10:3
		harfbuzz? ( media-libs/harfbuzz:= )
	)
	python? ( ${PYTHON_DEPS} )
	readline? ( sys-libs/readline:0= )
	woff2? ( media-libs/woff2:0= )
"
DEPEND="${RDEPEND}"
BDEPEND="
	sys-devel/gettext
	doc? ( >=dev-python/sphinx-2 )
	python? ( ${PYTHON_DEPS} )
	test? ( ${RDEPEND} )
"

PATCHES=(
	"${FILESDIR}"/fontforge-doc-no-warn-error.patch
)

pkg_setup() {
	use python && python-single-r1_pkg_setup
}

src_configure() {
	local mycmakeargs=(
		-DENABLE_DOCS=$(usex doc ON OFF)
		-DENABLE_LIBGIF=$(usex gif ON OFF)
		-DENABLE_LIBJPEG=$(usex jpeg ON OFF)
		-DENABLE_LIBPNG=$(usex png ON OFF)
		-DENABLE_LIBREADLINE=$(usex readline ON OFF)
		-DENABLE_LIBSPIRO=OFF # No package in Gentoo
		-DENABLE_LIBTIFF=$(usex tiff ON OFF)
		-DENABLE_MAINTAINER_TOOLS=OFF
		-DENABLE_PYTHON_EXTENSION=$(usex python ON OFF)
		-DENABLE_PYTHON_SCRIPTING=$(usex python ON OFF)
		-DENABLE_TILE_PATH=ON
		-DENABLE_WOFF2=$(usex woff2 ON OFF)
	)

	if use gtk; then
		mycmakeargs+=(
			-DENABLE_GUI=ON
			-DENABLE_HARFBUZZ=$(usex harfbuzz ON OFF)
		)
	else
		mycmakeargs+=( -DENABLE_GUI=OFF -DENABLE_HARFBUZZ=OFF )
	fi

	if use python; then
		python_setup
		mycmakeargs+=( -DPython3_EXECUTABLE="${PYTHON}" )
	fi

	if use truetype-debugger ; then
		local ft2="${ESYSROOT}/usr/include/freetype2"
		local ft2i="${ft2}/internal4fontforge"
		mycmakeargs+=(
			-DENABLE_FREETYPE_DEBUGGER="${ft2}"
			-DFreeTypeSource_INCLUDE_DIRS="${ft2};${ft2i}/include;${ft2i}/include/freetype;${ft2i}/src/truetype"
		)
	fi

	cmake_src_configure
}

src_install() {
	cmake_src_install
	docompress -x /usr/share/doc/${PF}/html
	einstalldocs
	find "${ED}" -name '*.la' -type f -delete || die
}
