# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DISTUTILS_EXT=1
DISTUTILS_USE_PEP517=setuptools
# No PYPI_VERIFY_REPO: upstream publishes the sdist without a PEP 740
# attestation, so /integrity/.../provenance is a hard 404 and the fetch fails.
# python3_10/python3_11 are _PYTHON_HISTORICAL_IMPLS in this tree
# (_PYTHON_ALL_IMPLS is 3.12..3.15), and pyo3 0.28 supports CPython up to
# 3.14 -- hence 12..14.
PYTHON_COMPAT=( python3_{12..15} )

CRATES="
	aho-corasick@1.1.5
	bit-set@0.8.0
	bit-vec@0.8.0
	bstr@1.13.1
	fancy-regex@0.19.2
	heck@0.5.0
	libc@0.2.191
	memchr@2.8.3
	once_cell@1.21.4
	portable-atomic@1.15.0
	proc-macro2@1.0.107
	pyo3-build-config@0.29.3
	pyo3-ffi@0.29.3
	pyo3-macros-backend@0.29.3
	pyo3-macros@0.29.3
	pyo3@0.29.3
	quote@1.0.47
	regex-automata@0.4.18
	regex-syntax@0.8.11
	regex@1.13.1
	rustc-hash@2.1.3
	serde_core@1.0.229
	serde_derive@1.0.229
	syn@2.0.119
	syn@3.0.9
	target-lexicon@0.13.5
	unicode-ident@1.0.27
"
# Upstream ships no Cargo.lock (it is gitignored), so the list above comes from
# `cargo generate-lockfile` on the sdist's own Cargo.toml, fed to pycargoebuild.
# Regenerate it on every bump: 0.13.0 moved pyo3 0.26 -> 0.28 and fancy-regex
# 0.13 -> 0.17, which alone rewrote 9 entries.
# 0.14.0 moved them again (pyo3 0.28 -> 0.29, fancy-regex 0.17 -> 0.19) and
# shipped with the 0.13 list, so it could not build until the list was redone.
# Highest MSRV among the crates is pyo3's 1.83, but tiktoken itself is
# edition = "2024", which needs >=1.85.
RUST_MIN_VER="1.85.0"

# The pypi eclass derives SRC_URI from ${PN}/${PV}; cargo.eclass only *computes*
# CARGO_CRATE_URIS, so the crate tarballs have to be appended explicitly.
inherit cargo distutils-r1 pypi

DESCRIPTION="Fast BPE tokeniser for use with OpenAI's models"
HOMEPAGE="
	https://github.com/openai/tiktoken/
	https://pypi.org/project/tiktoken/
"
SRC_URI+="
	${CARGO_CRATE_URIS}
"

LICENSE="MIT"
# Dependent crate licenses
LICENSE+=" Apache-2.0-with-LLVM-exceptions MIT Unicode-3.0"
SLOT="0"
KEYWORDS="~amd64"

# The "blobfile" extra (blobfile>=3) is deliberately not exposed as a USE flag:
# dev-python/blobfile exists in neither ::gentoo nor ::bentoo. It only enables
# reading BPE files from cloud object storage (az://, gs://, s3://); local and
# https:// loading works without it.
RDEPEND="
	dev-python/regex[${PYTHON_USEDEP}]
	dev-python/requests[${PYTHON_USEDEP}]
"
BDEPEND="
	>=dev-python/setuptools-rust-1.5.2[${PYTHON_USEDEP}]
"

QA_FLAGS_IGNORED="usr/lib.*/py.*/site-packages/tiktoken/_tiktoken.*\\.so"

# Every meaningful test calls tiktoken.get_encoding(), which downloads the BPE
# rank files from openaipublic.blob.core.windows.net at run time. There is no
# offline fixture to point at, so the suite cannot run under the network
# sandbox at all.
PROPERTIES="test_network"
RESTRICT="test"

EPYTEST_PLUGINS=()
distutils_enable_tests pytest
# NOTE: must be +=, distutils_enable_tests already appended pytest to BDEPEND.
BDEPEND+="
	test? (
		dev-python/hypothesis[${PYTHON_USEDEP}]
	)
"

src_unpack() {
	# cargo_src_unpack vendors every *.crate and `unpack`s everything else in
	# ${A} -- the PyPI sdist included -- so it covers both halves on its own.
	# NOT pypi_src_unpack: that one is only exported when PYPI_VERIFY_REPO is
	# set, and it reads USE=verify-provenance unconditionally, which without
	# PYPI_VERIFY_REPO is not in IUSE and dies.
	cargo_src_unpack
}
