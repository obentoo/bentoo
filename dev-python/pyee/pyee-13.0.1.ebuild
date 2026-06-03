# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{11..14} )

inherit distutils-r1 pypi

DESCRIPTION="A rough port of Node.js's EventEmitter to Python"
HOMEPAGE="
	https://github.com/jfhbrook/pyee/
	https://pypi.org/project/pyee/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

RDEPEND="
	dev-python/typing-extensions[${PYTHON_USEDEP}]
"
BDEPEND="
	>=dev-python/setuptools-scm-8[${PYTHON_USEDEP}]
"
