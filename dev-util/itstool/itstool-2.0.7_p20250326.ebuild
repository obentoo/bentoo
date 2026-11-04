# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{11..15} )
PYTHON_REQ_USE="xml(+)"

inherit autotools python-single-r1

DESCRIPTION="Translation tool for XML documents that uses gettext files and ITS rules"
HOMEPAGE="https://itstool.org/"

# use snapshot due to a lack of releases
COMMIT="19f9580f27aa261ea383b395fdef7e153f3f9e6d"
SRC_URI="https://github.com/itstool/itstool/archive/${COMMIT}.tar.gz -> ${P}.tar.gz"
SRC_URI+=" https://dev.gentoo.org/~sam/distfiles/${CATEGORY}/${PN}/${PN}-2.0.7-switch-to-lxml.patch.xz"
S="${WORKDIR}/${PN}-${COMMIT}"

# files in /usr/share/itstool/its are under a special exception || GPL-3+
LICENSE="GPL-3+"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~m68k ~mips ppc ppc64 ~riscv ~s390 ~sparc x86 ~x64-macos ~x64-solaris"

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="${PYTHON_DEPS}
	$(python_gen_cond_dep '
		dev-python/lxml[${PYTHON_USEDEP}]
	')"
DEPEND="${RDEPEND}"

DOCS=( NEWS ) # Changelog is missing; AUTHORS, README are empty

PATCHES=(
	"${WORKDIR}"/${PN}-2.0.7-switch-to-lxml.patch
	"${FILESDIR}"/${PN}-2.0.7-raw-string-testrunner.patch
)

src_prepare() {
	default
	eautoreconf
}

src_test() {
	"${PYTHON}" tests/run_tests.py || die "test suite failed"
}
