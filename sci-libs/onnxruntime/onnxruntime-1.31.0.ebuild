# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..14} )

inherit cmake edo flag-o-matic python-r1

EIGEN_COMMIT="1d8b82b0740839c0de7f1242a3585e3390ff5f33"

DESCRIPTION="Cross-platform, high performance ML inferencing and training accelerator"
HOMEPAGE="
	https://onnxruntime.ai
	https://github.com/microsoft/onnxruntime
"
SRC_URI="
	https://github.com/microsoft/onnxruntime/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://github.com/eigen-mirror/eigen/archive/${EIGEN_COMMIT}.tar.gz ->
		eigen-3.4.0_p20250216.tar.gz
"

LICENSE="MIT"
SLOT="0"
# ~amd64 only, and that is a packaging decision rather than an upstream
# limitation: upstream builds and publishes aarch64 artifacts. Story 002
# keyworded ~arm64 against a qemu-user chroot build that was descoped on
# 2026-08-08, which left the keyword asserting a build nobody had run.
# Shipping an unvalidated keyword is worse than shipping none: it tells an
# arm64 user the package was considered when it was only assumed. Restore
# ~arm64 together with a recorded arm64 build, not before.
KEYWORDS="~amd64"
IUSE="python test"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"
RESTRICT="!test? ( test )"

# The -bin package installs the same 26 paths this one does -- libonnxruntime.so
# and its SONAMEs, libonnxruntime_providers_shared.so, the whole
# /usr/include/onnxruntime tree, lib/cmake/onnxruntime/ and the .pc file. Same
# upstream, same version, same install prefix: they are two ways to get one
# library, not two libraries. Observed on 2026-08-08 as a real merge failure
# with -bin already installed, which is the only way this surfaces -- an
# unprivileged image build never runs collision-protect.
#
# Hard blocker rather than soft, matching sci-ml/lemonade{,-bin} in this
# overlay: portage cannot resolve the conflict by ordering, because neither
# package is an upgrade path for the other. One has to be unmerged by hand.
RDEPEND="
	!!sci-libs/onnxruntime-bin

	dev-cpp/abseil-cpp:=
	dev-libs/cpuinfo
	dev-libs/protobuf:=
	dev-libs/re2:=
	sci-ml/onnx[disableStaticReg]

	python? (
		${PYTHON_DEPS}
		dev-python/coloredlogs[${PYTHON_USEDEP}]
		dev-python/flatbuffers[${PYTHON_USEDEP}]
		>=dev-python/numpy-2[${PYTHON_USEDEP}]
		dev-python/packaging[${PYTHON_USEDEP}]
		dev-python/protobuf[${PYTHON_USEDEP}]
		dev-python/sympy[${PYTHON_USEDEP}]
		sci-ml/onnx[${PYTHON_USEDEP}]
	)
"
DEPEND="
	${RDEPEND}
	dev-cpp/ms-gsl
	dev-cpp/nlohmann_json
	dev-cpp/safeint
	dev-libs/boost
	dev-libs/date
	dev-libs/flatbuffers

	python? (
		dev-python/pybind11[${PYTHON_USEDEP}]
		sci-libs/dlpack
	)
"
BDEPEND="
	${PYTHON_DEPS}

	test? (
		dev-cpp/gtest
		$(python_gen_any_dep 'sci-ml/onnx[${PYTHON_USEDEP}]')

		python? ( dev-python/pytest[${PYTHON_USEDEP}] )
	)
"

# use-system-libraries is version-specific by construction, not by accident:
# most of its hunks take the upstream `PATCH_COMMAND ${Patch_EXECUTABLE} ...`
# lines as context, and upstream edits those every release. 1.30.0 dropped the
# `FIND_PACKAGE_ARGS NAMES cpuinfo` and `NAMES xnnpack` declarations and split
# the cpuinfo block into three branches (ARM64 / Linux / fallback), so three
# hunks were rejected -- and eapply aborts the whole src_prepare on a single
# rejection, which left 1.30.0 unbuildable for everyone. Reported and rebased
# by IlgazC in obentoo/bentoo#46. Dry-run every patch on a clean tree at each
# bump; the rename has to travel with it.
PATCHES=(
	"${FILESDIR}/${PN}-1.22.2-relax-the-dependency-on-flatbuffers.patch"
	"${FILESDIR}/${PN}-1.24.4-no-werror.patch"
	"${FILESDIR}/${PN}-1.30.0-use-system-libraries.patch"
)

CMAKE_USE_DIR="${S}/cmake"

# The `$(python_get_sitedir)/onnx/onnx-ml.proto` file is used during tests
python_check_deps() {
	! use test && return 0
	python_has_version "sci-ml/onnx[${PYTHON_USEDEP}]"
}

src_configure() {
	# Python is used at build time unconditionally
	python_setup

	local mycmakeargs=(
		-Donnxruntime_BUILD_SHARED_LIB=on

		-Donnxruntime_BUILD_UNIT_TESTS=$(usex test)
		-Donnxruntime_ENABLE_PYTHON=$(usex python)

		# Use the vendored Eigen at a specific 3.4-branch commit (2025-02-15),
		# fetched from the github eigen-mirror that upstream's own
		# `cmake/deps.txt` points at: gitlab.com now serves a Cloudflare 403 to
		# portage's wget, and the renamed archive is not on the gentoo mirrors.
		# ::gentoo's dev-cpp/eigen-3.4.0-r3 (Aug 2021) lacks 3+ years of fixes
		# onnxruntime depends on; eigen-3.4.9999 (live) would work but a live
		# ebuild as a build dependency is fragile. Eigen 5.0.1 (released 2026)
		# is a major API break onnxruntime's CMakeLists does not support yet.
		# Pointing FETCHCONTENT_SOURCE_DIR_EIGEN3 at the pre-fetched, hash-
		# pinned distfile is also what keeps CMake FetchContent off the network
		# during the build. Drop the vendoring once ::gentoo carries a tagged
		# 3.4.x release post-2025-02, or once upstream supports Eigen 5.x.
		-DFETCHCONTENT_SOURCE_DIR_EIGEN3="${WORKDIR}/eigen-${EIGEN_COMMIT}"

		# This makes it possible for `find_path` to find the `onnx-ml.proto` file
		-DCMAKE_INCLUDE_PATH="$(python_get_sitedir)"

		-Wno-dev
	)

	append-ldflags -Wl,-z,noexecstack

	if use python; then
		python_foreach_impl cmake_src_configure
	else
		cmake_src_configure
	fi
}

src_compile() {
	if use python; then
		python_foreach_impl cmake_src_compile
	else
		cmake_src_compile
	fi
}

# Adapted from `run_onnxruntime_tests` in `tools/ci_build/build.py`
python_test() {
	cd "${BUILD_DIR}" || die
	epytest --pyargs \
		onnxruntime_test_python.py \
		onnxruntime_test_python_backend.py \
		onnxruntime_test_python_mlops.py \
		onnxruntime_test_python_sparse_matmul.py
}

src_test() {
	# https://bugs.gentoo.org/975584
	local GTEST_SKIP_TESTS=(
		"ActivationOpNoInfTest.Softsign"
		"NhwcTransformerTests.ConvFloat_UsesNhwcOnlyWithKleidi"
		"Random.MultinomialDefaultDType"
		"Random.MultinomialGoodCase"
		"SamplingTest.Gpt2Sampling_CPU"
		"SignalOpsTest.DFT17_2D_complex_onesided_inverse"
		"SignalOpsTest.DFT17_IRFFT_naive"
		"SignalOpsTest.DFT17_IRFFT_radix2"
		"SignalOpsTest.DFT17_RFFT_IRFFT_roundtrip"
		"SignalOpsTest.DFT20_2D_complex_onesided_inverse"
		"SignalOpsTest.DFT20_IRFFT_naive"
		"SignalOpsTest.DFT20_IRFFT_radix2"
		"SignalOpsTest.DFT20_RFFT_IRFFT_roundtrip"
	)
	local -x GTEST_FILTER="*:-$(IFS=':'; echo "${GTEST_SKIP_TESTS[*]}")"

	if use python; then
		python_foreach_impl cmake_src_test
		python_foreach_impl python_test
	else
		cmake_src_test
	fi
}

# There is some custom logic in `setup.py`
python_install() {
	cd "${BUILD_DIR}" || die
	edo "${EPYTHON}" ../setup.py install \
		--prefix="${EPREFIX}/usr" \
		--root="${D}"

	rm -rf "${D}/$(python_get_sitedir)"/*.egg-info || die
	python_optimize
}

src_install() {
	if use python; then
		python_foreach_impl cmake_src_install
		python_foreach_impl python_install
	else
		cmake_src_install
	fi

	einstalldocs
}
