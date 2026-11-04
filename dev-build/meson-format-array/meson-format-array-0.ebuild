# Copyright 2020-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{11..15} )

inherit edo python-r1

DESCRIPTION="Format shell expressions into a meson array"
HOMEPAGE="https://wiki.gentoo.org/wiki/No_homepage"
S="${WORKDIR}"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~alpha amd64 arm arm64 ~hppa ~loong ~m68k ~mips ppc ppc64 ~riscv ~s390 ~sparc x86 ~arm64-macos ~x64-macos ~x64-solaris"

REQUIRED_USE="${PYTHON_REQUIRED_USE}"
RDEPEND="${PYTHON_DEPS}"

src_test() {
	run_doctest() {
		edo ${EPYTHON} -B -m doctest "${FILESDIR}/meson-format-array.py"
	}
	python_foreach_impl run_doctest
}

src_install() {
	python_foreach_impl python_newscript "${FILESDIR}"/meson-format-array.py meson-format-array
}
