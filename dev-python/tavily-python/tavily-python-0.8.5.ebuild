# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=setuptools
PYTHON_COMPAT=( python3_{12..15} )

# The pypi eclass derives SRC_URI and S from ${PN}/${PV}. It normalizes the
# project name ("-" -> "_"), which already yields the upstream sdist name
# tavily_python-${PV}.tar.gz, so no PYPI_PN/PYPI_NO_NORMALIZE override is
# needed. Note the PyPI project is "tavily-python" but the importable module
# is "tavily" (top_level.txt) — only the distribution carries the suffix.
inherit distutils-r1 pypi

DESCRIPTION="Python wrapper for the Tavily search API"
HOMEPAGE="
	https://github.com/tavily-ai/tavily-python
	https://pypi.org/project/tavily-python/
"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

# ::gentoo marks dev-python/httpx deprecated (encode/httpx no longer accepts
# bug reports), so pkgcheck reports DeprecatedDep here — expected, not a defect.
# It cannot be swapped for dev-python/httpx2: that is the Pydantic fork of the
# 2.x line, a separate package, and upstream tavily targets the 0.x API.
RDEPEND="
	dev-python/httpx[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
	>=dev-python/tiktoken-0.5.1[${PYTHON_USEDEP}]
"

# Upstream's own suite cannot run from the sdist: tests/test_custom_session.py
# and tests/test_session_pooling.py do "from tests.request_intercept import
# ...", but neither tests/request_intercept.py nor tests/__init__.py is shipped
# in the tarball (they exist only in the git tree), so pytest dies at
# collection. Fall back to import-check, which imports every module of the
# installed package ("tavily", "tavily.hybrid_rag", ...) and therefore still
# proves the runtime dependencies above are complete.
distutils_enable_tests import-check
