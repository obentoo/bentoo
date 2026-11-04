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
PYTHON_COMPAT=( python3_{11..15} )

inherit distutils-r1 pypi

DESCRIPTION="Pure-Python library and CLI tool for processing SBoM metadata"
HOMEPAGE="
	https://github.com/hughsie/python-uswid/
	https://pypi.org/project/uswid/
"

LICENSE="BSD-2-with-patent"
SLOT="0"
KEYWORDS="amd64 ~arm arm64 ~loong ~riscv x86"

RDEPEND="
	dev-python/cbor2[${PYTHON_USEDEP}]
	dev-python/lxml[${PYTHON_USEDEP}]
	dev-python/pefile[${PYTHON_USEDEP}]
"

distutils_enable_tests pytest
