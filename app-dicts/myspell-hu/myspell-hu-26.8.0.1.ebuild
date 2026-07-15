# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Version tracks the LibreOffice langpack this dictionary is extracted from:
# PV == LO_VER, so `bentoo overlay autoupdate` can follow the upstream source.
# The "libreoffice26.8" paths use the LO series (major.minor); if upstream moves
# to a new series, bump those paths accordingly.
LO_VER="${PV}"

MYSPELL_DICT=(
	"opt/libreoffice26.8/share/extensions/dict-hu/hu_HU.aff"
	"opt/libreoffice26.8/share/extensions/dict-hu/hu_HU.dic"
)

MYSPELL_HYPH=(
	"opt/libreoffice26.8/share/extensions/dict-hu/hyph_hu_HU.dic"
)

MYSPELL_THES=(
	"opt/libreoffice26.8/share/extensions/dict-hu/th_hu_HU_v2.dat"
	"opt/libreoffice26.8/share/extensions/dict-hu/th_hu_HU_v2.idx"
)

RPM_COMPRESS_TYPE="none"

inherit rpm myspell-r2

DESCRIPTION="Hungarian dictionaries for myspell/hunspell"
HOMEPAGE="http://magyarispell.sourceforge.net/"
SRC_URI="https://downloadarchive.documentfoundation.org/libreoffice/old/${LO_VER}/rpm/x86_64/LibreOffice_${LO_VER}_Linux_x86-64_rpm_langpack_hu.tar.gz"

LICENSE="GPL-3 GPL-2 LGPL-2.1 MPL-1.1"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~mips ppc ppc64 ~riscv ~sparc x86"
IUSE=""

src_unpack() {
	myspell-r2_src_unpack

	rpm_unpack ./LibreOffice_${LO_VER}_Linux_x86-64_rpm_langpack_hu/RPMS/libreoffice26.8-dict-hu-${LO_VER}-1.x86_64.rpm
}
