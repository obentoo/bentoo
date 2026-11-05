# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 pypi

DESCRIPTION="D-Bus signature parser built on pyparsing"
HOMEPAGE="
	https://github.com/stratis-storage/dbus-signature-pyparsing/
	https://pypi.org/project/dbus-signature-pyparsing/
"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"

RDEPEND="
	dev-python/pyparsing[${PYTHON_USEDEP}]
"
BDEPEND="
	test? (
		dev-python/hs-dbus-signature[${PYTHON_USEDEP}]
		dev-python/hypothesis[${PYTHON_USEDEP}]
	)
"

distutils_enable_tests unittest

python_test() {
	# tests/ is not a package: discover from inside it.
	eunittest -s tests
}
