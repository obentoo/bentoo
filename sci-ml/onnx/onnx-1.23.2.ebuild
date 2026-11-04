# Copyright 2022-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
# 1.23.2 ships no setup.py: pyproject.toml builds with
# scikit-build-core, so the setuptools backend override is gone.
DISTUTILS_USE_PEP517=scikit-build-core
DISTUTILS_EXT=1
# Based on ::gentoo's 1.20.1 ebuild, bumped to 1.23.2; python3_15 added.
# The Python build moved to scikit-build-core (CMake args via DISTUTILS_ARGS)
# and the runtime floors follow pyproject.toml (ml_dtypes>=0.5.4,
# protobuf>=6.31.1).
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added; ml-dtypes and protobuf floors from 1.23 pyproject.toml.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added; ml-dtypes and protobuf floors from 1.23 pyproject.toml.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added; scikit-build-core replaces setuptools as build backend.
# BENTOO-DIVERGENCE: KEYWORDS - bumped past ::gentoo, so overlay baseline ~amd64 only.
PYTHON_COMPAT=( python3_{11..15} )
inherit distutils-r1 cmake

DESCRIPTION="Open Neural Network Exchange (ONNX)"
HOMEPAGE="https://github.com/onnx/onnx"
SRC_URI="https://github.com/onnx/${PN}/archive/refs/tags/v${PV}.tar.gz
	-> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64"
IUSE="disableStaticReg"
RESTRICT="test"

RDEPEND="
	dev-cpp/abseil-cpp:=
	dev-libs/protobuf:=[protoc(+)]
	>=dev-python/ml-dtypes-0.5.4[${PYTHON_USEDEP}]
	dev-python/numpy[${PYTHON_USEDEP}]
	>=dev-python/protobuf-6.31.1[${PYTHON_USEDEP}]
	dev-python/typing-extensions[${PYTHON_USEDEP}]
"
DEPEND="${RDEPEND}"
BDEPEND="
	dev-python/nanobind[${PYTHON_USEDEP}]
"

src_prepare() {
	cmake_src_prepare
	distutils-r1_src_prepare
}

src_configure() {
	mycmakeargs=(
		-DONNX_USE_PROTOBUF_SHARED_LIBS=ON
		-DONNX_USE_LITE_PROTO=ON
		-DBUILD_SHARED_LIBS=ON
		-DONNX_DISABLE_STATIC_REGISTRATION=$(usex disableStaticReg ON OFF)
	)
	cmake_src_configure
}

python_compile() {
	# 1.23.2's CMakeLists.txt rejects ONNX_BUILD_PYTHON=ON together with
	# BUILD_SHARED_LIBS=ON: the extension links a static libonnx of its own,
	# while the shared libonnx comes from the plain cmake build above.
	local DISTUTILS_ARGS=(
		"${mycmakeargs[@]/-DBUILD_SHARED_LIBS=ON/-DBUILD_SHARED_LIBS=OFF}"
		-Dnanobind_DIR="$(python_get_sitedir)/nanobind/cmake"
	)
	# scikit-build-core's build-dir is in-tree (pyproject.toml); never let one
	# implementation reuse another's CMake cache.
	rm -rf .setuptools-cmake-build || die
	distutils-r1_python_compile
}

src_compile() {
	cmake_src_compile
	distutils-r1_src_compile
}

src_install() {
	cmake_src_install
	distutils-r1_src_install
}
