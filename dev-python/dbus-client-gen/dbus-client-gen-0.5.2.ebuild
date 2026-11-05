# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="Generates classes and methods useful to a D-Bus client"
HOMEPAGE="
	https://github.com/stratis-storage/dbus-client-gen/
	https://pypi.org/project/dbus-client-gen/
"

LICENSE="MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"

distutils_enable_tests unittest

python_test() {
	# tests/test_hypothesis.py imports tests/_introspect.py, which the PyPI
	# sdist does not ship: run only the deterministic module.
	eunittest -s tests -p test_deterministic.py
}
