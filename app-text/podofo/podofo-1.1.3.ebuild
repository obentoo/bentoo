# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

# extern/resources submodule as pinned by the 1.1.2 tag
RESOURCES_COMMIT="f3e6e289db3cb7fe0a1a21e65430f221fe598882"

DESCRIPTION="PoDoFo is a C++ library to work with the PDF file format"
HOMEPAGE="https://github.com/podofo/podofo"
SRC_URI="https://github.com/podofo/podofo/archive/refs/tags/${PV}.tar.gz -> ${P}.tar.gz
	test? (
		https://github.com/podofo/podofo-resources/archive/${RESOURCES_COMMIT}.tar.gz
			-> ${P}-test-resources.tar.gz
	)
"

# BENTOO-DIVERGENCE: LICENSE - no "tools? ( GPL-2+ )" branch, because this
# package never builds the tools (see PODOFO_BUILD_UNSUPPORTED_TOOLS below).
# Only the LGPL-2+ library is installed.
LICENSE="LGPL-2+"

# BENTOO-DIVERGENCE: SLOT - ::gentoo's usable podofo is 0/2 (PoDoFo 0.10.x).
# It added 1.1.2 as SLOT 0/4 on 2026-10-20 but masks >=app-text/podofo-1
# (bug #984580: it breaks a major reverse dependency), which is exactly the
# clash this private slot avoids. Revisit once that mask is lifted. The 1.x API is a
# hard source break: PdfErrorCode::Flate became FlateError,
# PdfOutlineItem::CreateChild() lost an argument, page appending moved to
# PdfPageCollection::AppendDocumentPages(), and PdfMemDocument grew
# CreateDestination(). Consumers cannot be ported one at a time against a single
# shared install, so this slot lives entirely inside a private prefix and
# coexists with app-text/podofo:0:
#
#   headers   /usr/include/podofo-1/podofo/
#   library   /usr/$(get_libdir)/podofo-1/
#
# Nothing lands in a default search path, so a consumer opts in explicitly.
# Today that is app-text/calibre alone, which moved to the 1.x API in 9.15.0 and
# points setup.py at the prefix through PODOFO_INC_DIR/PODOFO_LIB_DIR plus an
# RPATH. app-office/scribus and kde-misc/krename keep using :0 from ::gentoo,
# untouched. The subslot is upstream's SOVERSION (4 here, 2 in the 0.10.x line).
SLOT="1/4"

# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only, where ::gentoo keywords several
# arches. This is an overlay-owned slot, not a ::gentoo mirror, so it follows
# the overlay baseline: amd64 (x86-64-v3) is the only architecture bentoo can
# test, and a keyword is a promise that the package works there.
KEYWORDS="~amd64"

# BENTOO-DIVERGENCE: IUSE - "lcms" is new (1.x added PODOFO_WITH_LCMS2 for ICC
# profile reading), while "idn" and "tools" are gone: 1.x dropped the libidn
# dependency outright, and the tools are unsupported upstream and would install
# binaries colliding with :0.
# BENTOO-DIVERGENCE: IUSE_DEFAULTS - fontconfig, jpeg and png default on, where
# ::gentoo leaves all three off. Turning any of them off silently removes a
# feature app-text/calibre uses (font embedding, image extraction), and calibre
# depends on [jpeg,png] for that reason.
IUSE="+fontconfig +jpeg lcms +png test tiff"
RESTRICT="!test? ( test )"

# BENTOO-DIVERGENCE: DEPEND - media-libs/lcms replaces net-dns/libidn: 1.x
# removed the libidn code path and added optional little-cms2 support.
# BENTOO-DIVERGENCE: RDEPEND - the same swap, this is where it is written.
# BENTOO-DIVERGENCE: metadata.xml - describes the private-prefix arrangement
# above, which has no counterpart in ::gentoo's file.
RDEPEND="
	dev-libs/libxml2:=
	dev-libs/openssl:=
	media-libs/freetype:2=
	virtual/zlib:=
	fontconfig? ( media-libs/fontconfig:= )
	jpeg? ( media-libs/libjpeg-turbo:= )
	lcms? ( media-libs/lcms:2= )
	png? ( media-libs/libpng:= )
	tiff? ( media-libs/tiff:= )
"
DEPEND="${RDEPEND}"
BDEPEND="
	virtual/pkgconfig
	test? ( fontconfig? ( media-fonts/liberation-fonts ) )
"

# BENTOO-DIVERGENCE: PATCHES - ::gentoo's test-output patch only, without its
# podofo-1.1.2-fmt-uint128.patch: that one fixes the bundled fmt's fallback
# uint128, used only on targets with no native __int128, which amd64 and arm64
# both have.
PATCHES=(
	"${FILESDIR}"/${PN}-1.1.2-test-output.patch
)

src_prepare() {
	cmake_src_prepare

	if use test; then
		rmdir extern/resources || die
		mv "${WORKDIR}/podofo-resources-${RESOURCES_COMMIT}" extern/resources || die
	fi
}

src_configure() {
	# The 3rdparty/ directory (fmt, date, fastfloat, utf8cpp, utf8proc,
	# tcbspan) stays vendored: upstream tracks unreleased revisions of those
	# and the PODOFO_DEVENDOR_* switches demand exactly the pinned ones.
	local mycmakeargs=(
		# private prefix -- see the SLOT comment above
		-DCMAKE_INSTALL_INCLUDEDIR="include/podofo-1"
		-DCMAKE_INSTALL_LIBDIR="$(get_libdir)/podofo-1"

		-DPODOFO_BUILD_STATIC=FALSE
		-DPODOFO_BUILD_TEST=$(usex test TRUE FALSE)
		-DPODOFO_BUILD_EXAMPLES=FALSE
		# tools would install podofo* binaries that collide with :0
		-DPODOFO_BUILD_UNSUPPORTED_TOOLS=FALSE

		-DPODOFO_WITH_FONTMANAGER=$(usex fontconfig ON OFF)
		-DPODOFO_WITH_LCMS2=$(usex lcms ON OFF)
		$(cmake_use_find_package jpeg JPEG)
		$(cmake_use_find_package png PNG)
		$(cmake_use_find_package tiff TIFF)
	)

	cmake_src_configure
}

src_test() {
	local CMAKE_SKIP_TESTS=(
		# TestSaveOnSigning loads ReferenceImage.png for the signature appearance.
		$(usev !png '^TestImage3$ ^TestSaveOnSigning$')
		$(usev !jpeg '^TestImage(2|4|5)$')
		$(usev !tiff '^TestImage(7|8)$')
	)

	if ! use fontconfig; then
		# These tests search for system fonts by name.
		CMAKE_SKIP_TESTS+=(
			'^TestLoadEncrypedFilePdfMemDocument$'
			'^TestLoadEncrypedFilePdfParser$'
			'^TestCreateDelete$'
			'^TestDrawTextMultipleTimes$'
			'^TestEmbedFont$'
		)
	fi

	cmake_src_test
}
