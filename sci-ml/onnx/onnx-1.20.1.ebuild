# Copyright 2022-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
DISTUTILS_UPSTREAM_PEP517=standalone
DISTUTILS_USE_PEP517=setuptools
DISTUTILS_EXT=1
# Mirrored from ::gentoo only to add python3_15: no code change is needed
# for it. Drop this copy once ::gentoo lists python3_15.
# BENTOO-DIVERGENCE: IUSE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: REQUIRED_USE - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: DEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: RDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
# BENTOO-DIVERGENCE: BDEPEND - python3_15 added to PYTHON_COMPAT, nothing else.
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
