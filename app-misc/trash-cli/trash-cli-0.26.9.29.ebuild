# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
# Based on ::gentoo's 0.24.5.26 ebuild, bumped ahead of ::gentoo to 0.26.9.29;
# python3_15 added. No other change. Drop this copy once ::gentoo ships
# >=0.26.9.29 with python3_15. dev-vcs/gitkraken needs it on python3_15-only hosts.
# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 only: a bump past ::gentoo is no longer a mirror,
# so it follows the overlay baseline (amd64, x86-64-v3).
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{11..15} )
inherit distutils-r1

DESCRIPTION="Python scripts to manipulate trash cans via the command line"
HOMEPAGE="https://github.com/andreafrancia/trash-cli"
SRC_URI="https://github.com/andreafrancia/${PN}/archive/${PV}.tar.gz -> ${P}.gh.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	dev-python/psutil[${PYTHON_USEDEP}]
	dev-python/six[${PYTHON_USEDEP}]
"
BDEPEND="
	test? (
		dev-python/flexmock[${PYTHON_USEDEP}]
		dev-python/mock[${PYTHON_USEDEP}]
		dev-python/parameterized[${PYTHON_USEDEP}]
	)
"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest

src_test() {
	local -x COLUMNS=80
	distutils-r1_src_test
}
