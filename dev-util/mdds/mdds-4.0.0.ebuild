# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://gitlab.com/mdds/mdds.git"
	inherit git-r3
else
	# For 3.0.0, it mysteriously redirects to 2.0.0
	#SRC_URI="https://kohei.us/files/${PN}/src/${P}.tar.xz"
	SRC_URI="https://gitlab.com/api/v4/projects/mdds%2Fmdds/packages/generic/source/${PV}/${P}.tar.xz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc ~ppc64 ~riscv ~x86"
fi
inherit autotools toolchain-funcs

DESCRIPTION="Collection of multi-dimensional data structure and indexing algorithm"
HOMEPAGE="https://gitlab.com/mdds/mdds"

LICENSE="MIT"
SLOT="1/4.0" # Check API version on version bumps!
IUSE="doc openmp test"
RESTRICT="!test? ( test )"

DEPEND="dev-libs/boost:="
RDEPEND="${DEPEND}"
BDEPEND="
	doc? (
		app-text/doxygen
		dev-python/sphinx
	)
	test? ( dev-util/dejagnu )
"

# BENTOO-DIVERGENCE: SLOT - 4.0.0 raises the API version to 4.0 (it installs
# mdds-4.0.pc), so the subslot is 1/4.0; consumers pinned to :1/3.0
# (liborcus-0.21, libreoffice-26.x) keep mdds-3.2.1.
# BENTOO-DIVERGENCE: PATCHES - ours, ::gentoo has no 4.0.0: the 3.2.1
# buildsystem patch minus its EXTRA_DIST hunk (4.0.0 no longer lists
# CHANGELOG and LICENSE there), regenerated so it applies without fuzz.
PATCHES=(
	"${FILESDIR}/${PN}-4.0.0-buildsystem.patch"
)

pkg_pretend() {
	[[ ${MERGE_TYPE} != binary ]] && use openmp && tc-check-openmp
}

pkg_setup() {
	[[ ${MERGE_TYPE} != binary ]] && use openmp && tc-check-openmp
}

src_prepare() {
	default
	eautoreconf
}

src_configure() {
	local myeconfargs=(
		$(use_enable doc docs)
		$(use_enable openmp)
	)
	econf "${myeconfargs[@]}"
}

src_test() {
	tc-export CXX
	default
}
