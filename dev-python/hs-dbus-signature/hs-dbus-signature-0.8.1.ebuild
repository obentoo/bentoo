# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="D-Bus signature hypothesis strategy generator"
HOMEPAGE="
	https://github.com/mulkieran/hs-dbus-signature/
	https://pypi.org/project/hs-dbus-signature/
"

LICENSE="MPL-2.0"
SLOT="0"
KEYWORDS="~amd64"

# hypothesis is a runtime dependency: the package IS a hypothesis strategy.
RDEPEND="
	dev-python/hypothesis[${PYTHON_USEDEP}]
"

distutils_enable_tests unittest

python_test() {
	# tests/ is not a package: discover from inside it.
	eunittest -s tests
}
