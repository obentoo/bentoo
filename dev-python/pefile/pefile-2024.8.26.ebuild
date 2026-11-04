# Copyright 1999-2025 Gentoo Authors
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
PYTHON_COMPAT=( python3_{10..15} )
inherit distutils-r1

DESCRIPTION="Module to read and work with Portable Executable (PE) files"
HOMEPAGE="https://github.com/erocarrera/pefile"

if [[ ${PV} == 9999 ]] ; then
	EGIT_REPO_URI="https://github.com/erocarrera/pefile.git"
	inherit git-r3
else
	SRC_URI="https://github.com/erocarrera/pefile/releases/download/v${PV}/${P}.tar.gz -> ${P}.gh.tar.gz"
	KEYWORDS="amd64 arm arm64 ~loong ppc ppc64 ~riscv x86"
fi

LICENSE="MIT"
SLOT="0"

# Unfortunately there is nothing we can test here. Upstream doesn't ship a test
# suite inside the release files. The test fixtures in the source repo is
# encrypted so that only their CI pipeline is able to run the tests.
RESTRICT="test"
