# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="Colored stream handler for the logging module"
HOMEPAGE="
	https://pypi.org/project/coloredlogs/
	https://github.com/xolox/python-coloredlogs
	https://coloredlogs.readthedocs.io/en/latest/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="amd64 ~arm ~x86"

RDEPEND="
	>=dev-python/humanfriendly-9.1[${PYTHON_USEDEP}]"
BDEPEND="
	test? (
		dev-python/capturer[${PYTHON_USEDEP}]
		dev-python/coverage[${PYTHON_USEDEP}]
		dev-python/mock[${PYTHON_USEDEP}]
		dev-python/verboselogs[${PYTHON_USEDEP}]
	)
"

PATCHES=(
	"${FILESDIR}/${PN}-14.0-fix-install-prefix.patch"
	"${FILESDIR}/${PN}-15.0.1-py3.13.patch"
)

distutils_enable_sphinx docs
EPYTEST_PLUGINS=()
distutils_enable_tests pytest

EPYTEST_DESELECT=(
	# test_auto_install fails because the pth file isn't being loaded
	coloredlogs/tests.py::ColoredLogsTestCase::test_auto_install
)

python_test() {
	epytest coloredlogs/tests.py
}
