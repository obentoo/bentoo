# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="Computing with and displaying bytes"
HOMEPAGE="
	https://github.com/mulkieran/justbytes/
	https://pypi.org/project/justbytes/
"

LICENSE="LGPL-2.1+"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	>=dev-python/justbases-0.13[${PYTHON_USEDEP}]
"

# The PyPI sdist ships no test suite.
