# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_USE_PEP517=hatchling
PYTHON_COMPAT=( python3_{12..14} )

inherit distutils-r1 pypi

DESCRIPTION="The official Python library for the OpenAI API"
HOMEPAGE="
	https://github.com/openai/openai-python
	https://pypi.org/project/openai/
"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

# Upstream extras mapped to USE flags.  Three extras are deliberately NOT
# exposed because at least one of their packages is missing from ::gentoo and
# ::bentoo -- a USE flag nobody can enable is worse than no flag at all:
#   datalib       -> dev-python/pandas-stubs is not packaged (numpy and pandas
#                    are, so only the type stubs are blocking this one).
#   realtime      -> upstream pins websockets>=13,<16 and the only versions in
#                    ::gentoo are >=16.0, so the range is unsatisfiable.
#   voice-helpers -> dev-python/sounddevice is not packaged.
IUSE="aiohttp bedrock"

RDEPEND="
	>=dev-python/anyio-4.10.0[${PYTHON_USEDEP}]
	<dev-python/anyio-5[${PYTHON_USEDEP}]
	>=dev-python/distro-1.7.0[${PYTHON_USEDEP}]
	<dev-python/distro-2[${PYTHON_USEDEP}]
	>=dev-python/httpx2-2.7.0[${PYTHON_USEDEP}]
	<dev-python/httpx2-3[${PYTHON_USEDEP}]
	>=dev-python/jiter-0.10.0[${PYTHON_USEDEP}]
	<dev-python/jiter-1[${PYTHON_USEDEP}]
	>=dev-python/pydantic-1.9.0[${PYTHON_USEDEP}]
	<dev-python/pydantic-3[${PYTHON_USEDEP}]
	dev-python/sniffio[${PYTHON_USEDEP}]
	>dev-python/tqdm-4-r0[${PYTHON_USEDEP}]
	>=dev-python/typing-extensions-4.14[${PYTHON_USEDEP}]
	<dev-python/typing-extensions-5[${PYTHON_USEDEP}]
	aiohttp? ( >=dev-python/aiohttp-3.14.1[${PYTHON_USEDEP}] )
	bedrock? (
		>=dev-python/botocore-1.40.0[${PYTHON_USEDEP}]
		<dev-python/botocore-2[${PYTHON_USEDEP}]
	)
"

# The project readme is a dynamic metadata field produced by the
# hatch-fancy-pypi-readme build hook; without it the hatchling backend aborts.
BDEPEND="dev-python/hatch-fancy-pypi-readme[${PYTHON_USEDEP}]"

# Nearly the whole suite (everything under tests/api_resources) talks to a
# Prism mock API server that upstream expects on http://127.0.0.1:4010, and
# upstream ships no marker that separates those from the offline tests.
RESTRICT="test"
