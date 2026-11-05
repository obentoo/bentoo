# Copyright 2022-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
DISTUTILS_UPSTREAM_PEP517=standalone
DISTUTILS_USE_PEP517=setuptools
DISTUTILS_EXT=1
# Mirrored from ::gentoo only to add python3_15. Drop this copy once
# ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: src_prepare - setup.py falls back to nanobind's .abi3.so name (python3_15).
PYTHON_COMPAT=( python3_{11..15} )
inherit distutils-r1 cmake

DESCRIPTION="Open Neural Network Exchange (ONNX)"
HOMEPAGE="https://github.com/onnx/onnx"
SRC_URI="https://github.com/onnx/${PN}/archive/refs/tags/v${PV}.tar.gz
	-> ${P}.tar.gz"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="disableStaticReg"
RESTRICT="test"

RDEPEND="
	dev-cpp/abseil-cpp:=
	dev-libs/protobuf:=[protoc(+)]
	dev-python/ml-dtypes[$PYTHON_USEDEP]
	dev-python/numpy[${PYTHON_USEDEP}]
	dev-python/protobuf[${PYTHON_USEDEP}]
	dev-python/typing-extensions[$PYTHON_USEDEP]
"
DEPEND="${RDEPEND}"
BDEPEND="
	dev-python/nanobind[${PYTHON_USEDEP}]
"

src_prepare() {
	cmake_src_prepare
	distutils-r1_src_prepare

	# Python 3.15 lists ".abi3-<multiarch>.so" first in EXTENSION_SUFFIXES, so
	# setuptools names the module onnx_cpp2py_export.abi3-x86_64-linux-gnu.so,
	# while nanobind's CMake still writes onnx_cpp2py_export.abi3.so and
	# BuildExt dies with "can't copy ... doesn't exist". Fall back to the file
	# nanobind wrote; 3.15 imports both names. No-op on 3.12-3.14.
	grep -qF '            src = os.path.join(lib_dir, filename)' setup.py \
		|| die "setup.py: BuildExt src line moved, re-check the abi3 fallback"
	sed -i '/^            src = os.path.join(lib_dir, filename)$/a\
\            if not os.path.exists(src):\
\                src = os.path.join(lib_dir, fullname.rpartition(".")[2] + ".abi3.so")' \
		setup.py || die
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
	local mycmakeargs=(
		"${mycmakeargs[@]}"
		-Dnanobind_DIR="$(python_get_sitedir)/nanobind/cmake"
	)
	rm -rf .setuptools-cmake-build || die
	CMAKE_ARGS="${mycmakeargs[@]}" distutils-r1_python_compile
}

src_compile() {
	cmake_src_compile
	distutils-r1_src_compile
}

src_install() {
	cmake_src_install
	distutils-r1_src_install
}
