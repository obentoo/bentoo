# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="Generates dbus-python client code from D-Bus introspection data"
HOMEPAGE="
	https://github.com/stratis-storage/dbus-python-client-gen/
	https://pypi.org/project/dbus-python-client-gen/
"

LICENSE="MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	dev-python/dbus-python[${PYTHON_USEDEP}]
	>=dev-python/into-dbus-python-0.8[${PYTHON_USEDEP}]
"

# The sdist's only test module imports tests/_introspect.py, which the PyPI
# sdist does not ship, so there is no runnable test suite.
