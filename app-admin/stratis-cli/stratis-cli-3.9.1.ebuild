# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="Command-line tool to manage Stratis storage through stratisd"
HOMEPAGE="
	https://stratis-storage.github.io/
	https://github.com/stratis-storage/stratis-cli/
	https://pypi.org/project/stratis-cli/
"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
# The PyPI sdist ships no tests; upstream's suite needs a running stratisd on
# the system bus.
RESTRICT="test"

# dbus-python is imported directly, but upstream declares it only transitively.
RDEPEND="
	>=dev-python/dbus-client-gen-0.4[${PYTHON_USEDEP}]
	dev-python/dbus-python[${PYTHON_USEDEP}]
	>=dev-python/dbus-python-client-gen-0.8.4[${PYTHON_USEDEP}]
	>=dev-python/justbytes-0.14[${PYTHON_USEDEP}]
	dev-python/packaging[${PYTHON_USEDEP}]
	dev-python/psutil[${PYTHON_USEDEP}]
	dev-python/python-dateutil[${PYTHON_USEDEP}]
	dev-python/wcwidth[${PYTHON_USEDEP}]
	sys-fs/stratisd
"
