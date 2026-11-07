# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Upstream keeps its metadata in setup.py (name, deps, entry points); the
# pyproject.toml here only carries black/isort/mypy/bandit/pytest/uv config and
# has no [project] table, so the backend is plain setuptools.
DISTUTILS_USE_PEP517=setuptools
# Narrowed to 3.14 by USE=api, not by upstream: dev-python/fastapi is
# PYTHON_COMPAT=( python3_{14..15} ), so on 3.12/3.13 that flag has no
# solution and pkgcheck reports it as a nonsolvable depset on every profile.
# Widen this again once fastapi supports the older interpreters.
PYTHON_COMPAT=( python3_14 )
# sci-ml/transformers and sci-ml/accelerate are DISTUTILS_SINGLE_IMPL (they sit
# on top of sci-ml/pytorch, which is built for one interpreter), and GAIA
# imports both from its core.  A multi-impl build here cannot satisfy them:
# they expose PYTHON_SINGLE_TARGET, not PYTHON_TARGETS.
DISTUTILS_SINGLE_IMPL=1

# The pypi eclass normalizes ${PN} to the sdist name (amd-gaia -> amd_gaia) and
# sets both SRC_URI and S from it, so neither is declared here.
inherit distutils-r1 pypi

DESCRIPTION="Agent framework that runs locally against an OpenAI-compatible LLM server"
HOMEPAGE="https://github.com/amd/gaia https://pypi.org/project/amd-gaia/"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64"

# IUSE maps upstream extras_require, but only the extras whose every dependency
# already exists in ::gentoo or ::bentoo.  The rest are deliberately absent:
#
#   image    -> dev-python/term-image missing
#   litellm  -> dev-python/litellm missing
#   mcp      -> dev-python/mcp missing (starlette and uvicorn are present)
#   telegram -> dev-python/python-telegram-bot missing
#   blender  -> the standalone `bpy` module is missing (media-gfx/blender does
#               not install an importable bpy for the system interpreter)
#   audio    -> torchaudio missing (sci-ml/pytorch and sci-ml/torchvision exist)
#   rag      -> faiss-cpu, pymupdf, python-pptx and python-docx all missing
#   ui       -> the rag set above plus sentence-transformers, all missing
#   eval     -> dev-python/anthropic and dev-python/tiktoken missing
#   talk     -> sounddevice, openai-whisper and kokoro missing
#   youtube  -> llama-index-readers-youtube-transcript missing
#
#   dev / lint / publish are upstream's own toolchains (pytest, black, mypy,
#   build, twine) and are not runtime features, so they are not USE flags.
IUSE="api"

# transformers and accelerate live in sci-ml/, not dev-python/.
# pywin32 from install_requires is dropped: its marker is sys_platform=="win32".
RDEPEND="
	sci-ml/accelerate[${PYTHON_SINGLE_USEDEP}]
	sci-ml/transformers[${PYTHON_SINGLE_USEDEP}]
	$(python_gen_cond_dep '
		dev-python/aiohttp[${PYTHON_USEDEP}]
		dev-python/beautifulsoup4[${PYTHON_USEDEP}]
		dev-python/openai[${PYTHON_USEDEP}]
		dev-python/python-dotenv[${PYTHON_USEDEP}]
		dev-python/requests[${PYTHON_USEDEP}]
		dev-python/rich[${PYTHON_USEDEP}]
		>=dev-python/apscheduler-3.10.0[${PYTHON_USEDEP}]
		>=dev-python/cryptography-42.0.0[${PYTHON_USEDEP}]
		>=dev-python/keyring-24.0.0[${PYTHON_USEDEP}]
		<dev-python/keyring-26[${PYTHON_USEDEP}]
		>=dev-python/pillow-9.0.0[${PYTHON_USEDEP}]
		>=dev-python/pydantic-2.9.2[${PYTHON_USEDEP}]
		>=dev-python/python-multipart-0.0.9[${PYTHON_USEDEP}]
		>=dev-python/tavily-python-0.5.0[${PYTHON_USEDEP}]
		>=dev-python/tomli-w-1.0.0[${PYTHON_USEDEP}]
		>=dev-python/watchdog-2.1.0[${PYTHON_USEDEP}]
	')
	api? (
		$(python_gen_cond_dep '
			>=dev-python/fastapi-0.115.0[${PYTHON_USEDEP}]
			>=dev-python/httpx-0.27.0[${PYTHON_USEDEP}]
			>=dev-python/uvicorn-0.32.0[${PYTHON_USEDEP}]
		')
	)
"
# dev-python/tomli is deliberately absent from RDEPEND.  Upstream guards it with
# python_version < '3.11' because from 3.11 on the same parser is tomllib in the
# stdlib, and this tree's live implementations start at 3.12 — so no interpreter
# we build for can ever need it.  Restore the dep only if PYTHON_COMPAT is ever
# widened below 3.11.

# The whole tests/ directory in the sdist talks to a live Lemonade server:
# 15 of the 16 files reference a lemonade endpoint, localhost or an API key
# (tests/test_lemonade_health.py drives requests against the running server's
# /health), and pyproject.toml marks the rest as integration / real_model /
# network.  None of that is reachable from the build sandbox.
RESTRICT="test"

# src/gaia/apps/webui/dist/ is shipped pre-bundled in the sdist (minified JS/CSS
# plus woff2 fonts) and is installed as package_data.  There is no npm/node step
# to run and no sources to rebuild it from — do NOT add a nodejs build phase.

pkg_postinst() {
	elog "GAIA does not serve models itself: it drives an OpenAI-compatible"
	elog "server.  The backend packaged in this overlay is sci-ml/lemonade;"
	elog "point GAIA at it with GAIA_BASE_URL or gaia's own configuration."
	if ! use api; then
		elog
		elog "USE=api adds fastapi/uvicorn/httpx, needed by the local REST"
		elog "server (gaia api) and by the browser UI it serves."
	fi
}
