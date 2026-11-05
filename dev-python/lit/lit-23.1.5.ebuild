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
PYTHON_COMPAT=( python3_{12..15} )

inherit distutils-r1 llvm.org

DESCRIPTION="A stand-alone install of the LLVM suite testing tool"
HOMEPAGE="https://llvm.org/"

LICENSE="Apache-2.0-with-LLVM-exceptions UoI-NCSA"
SLOT="0"
KEYWORDS="~amd64 ~arm ~arm64 ~loong ~mips ~ppc ~ppc64 ~riscv ~sparc ~x86"
IUSE="test"
RESTRICT="!test? ( test )"

# Tests require 'FileCheck' and 'not' utilities (from llvm)
BDEPEND="
	test? (
		dev-python/psutil[${PYTHON_USEDEP}]
		llvm-core/llvm
	)
"

LLVM_COMPONENTS=( llvm/utils/lit )
llvm.org_set_globals

# TODO: move the manpage generation here (from llvm-core/llvm)

src_prepare() {
	cd "${WORKDIR}" || die
	distutils-r1_src_prepare
}

python_test() {
	local -x LIT_PRESERVES_TMP=1
	local litflags=$(get_lit_flags)
	./lit.py ${litflags//;/ } tests || die
}
