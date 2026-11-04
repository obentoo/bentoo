# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{12..15} )
PYTHON_REQ_USE="threads(+)"
DISTUTILS_USE_PEP517=setuptools
inherit distutils-r1 pypi

DESCRIPTION="Human friendly output for text interfaces using Python"
HOMEPAGE="https://pypi.org/project/humanfriendly/
	https://github.com/xolox/python-humanfriendly/
	https://humanfriendly.readthedocs.io/"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 ~arm ~x86"

BDEPEND="
	test? (
		dev-python/capturer[${PYTHON_USEDEP}]
		>=dev-python/coloredlogs-15.0.1[${PYTHON_USEDEP}]
		dev-python/docutils[${PYTHON_USEDEP}]
		dev-python/mock[${PYTHON_USEDEP}]
	)
"

PATCHES=(
	"${FILESDIR}/${PN}-10.0-py3.13.patch"
)

EPYTEST_PLUGINS=()
distutils_enable_tests pytest
distutils_enable_sphinx docs

python_test() {
	epytest humanfriendly/tests.py
}
