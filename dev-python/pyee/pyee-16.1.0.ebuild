# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# 16.1.0 moved its build backend from setuptools(-scm) to hatchling and
# raised requires-python to >=3.12; the version is now static in pyproject.toml.
DISTUTILS_USE_PEP517=hatchling
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="A rough port of Node.js's EventEmitter to Python"
HOMEPAGE="
	https://github.com/jfhbrook/pyee/
	https://pypi.org/project/pyee/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	dev-python/typing-extensions[${PYTHON_USEDEP}]
"
