# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

ROCM_VERSION="6.3"

inherit cmake cuda rocm linux-info

# Upstream publishes no usable release tags: the repository carries exactly one
# tag (t0002, a prerelease from 2025-07-22) and nothing resembling the b<N>
# series sci-ml/llama-cpp pins to.  The package is therefore pinned to a dated
# commit snapshot, following sys-kernel/linux-firmware and app-editors/zed.
#
# Pinned commit 9d07d8681ece159a89fb4e16a1f9c9f3a5fac20f, committed
# 2026-07-18 -- the date stamp in ${PV} is that committer date.  Bump by
# picking a new HEAD, setting MY_COMMIT and moving ${PV} to its committer date.
MY_COMMIT="9d07d8681ece159a89fb4e16a1f9c9f3a5fac20f"

DESCRIPTION="llama.cpp fork with additional SOTA quants and improved performance"
HOMEPAGE="https://github.com/ikawrakow/ik_llama.cpp"
SRC_URI="https://github.com/ikawrakow/ik_llama.cpp/archive/${MY_COMMIT}.tar.gz -> ${P}.tar.gz"
S="${WORKDIR}/ik_llama.cpp-${MY_COMMIT}"

LICENSE="MIT"
SLOT="0"

# Deliberately ~amd64 only, unlike sci-ml/llama-cpp.  The fork's reason to
# exist is its SOTA quantizations, which are hand-written for AVX2/AVX512; the
# ARM paths are far less exercised upstream and this snapshot has never been
# built on arm64.  Promote only after a real arm64 chroot build.
KEYWORDS="~amd64"

# Only the flags this fork's ggml actually honours are exposed.  It predates
# the GGML_SSE42/GGML_BMI2/GGML_AMX_* options that sci-ml/llama-cpp drives, and
# spells AVX-VNNI "GGML_AVXVNNI" rather than "GGML_AVX_VNNI".
X86_CPU_FLAGS=(
	avx
	avx_vnni
	avx2
	avx512f avx512cd avx512vl avx512dq avx512bw
	avx512vbmi
	avx512_vnni
	avx512_bf16
	fma3
	f16c
)
CPU_FLAGS=( "${X86_CPU_FLAGS[@]/#/cpu_flags_x86_}" )

IUSE="curl cuda +openmp hip vulkan ${CPU_FLAGS[*]}"

REQUIRED_USE="
	hip? ( ${ROCM_REQUIRED_USE} )
"

# curl is needed for pulling models from huggingface
CDEPEND="
	curl? ( net-misc/curl:= )
	openmp? ( llvm-runtimes/openmp:= )
	hip? (
		>=dev-util/hip-${ROCM_VERSION}
		>=sci-libs/hipBLAS-${ROCM_VERSION}
		>=sci-libs/rocBLAS-${ROCM_VERSION}
	)
	cuda? ( dev-util/nvidia-cuda-toolkit:= )
"
DEPEND="${CDEPEND}
	vulkan? ( dev-util/vulkan-headers )
"
RDEPEND="${CDEPEND}
	vulkan? ( media-libs/vulkan-loader )
"
BDEPEND="
	vulkan? ( media-libs/shaderc )
"

pkg_setup() {
	if use hip; then
		linux-info_pkg_setup
		if linux-info_get_any_version && linux_config_exists; then
			if ! linux_chkconfig_present HSA_AMD_SVM; then
				ewarn "To use ROCm/HIP, you need to have HSA_AMD_SVM option enabled in your kernel."
			fi
		fi
	fi
}

src_prepare() {
	use cuda && cuda_src_prepare
	cmake_src_prepare

	# build-info.cmake sets BUILD_NUMBER/BUILD_COMMIT as plain variables, which
	# shadow anything passed as -DBUILD_NUMBER=/-DBUILD_COMMIT= on the command
	# line, and its git probe finds no repository inside a release tarball.
	# Patch the defaults instead, so the installed binaries report the snapshot
	# they were built from rather than "build 0 (unknown)".
	sed -i \
		-e "s/^set(BUILD_NUMBER 0)$/set(BUILD_NUMBER ${PV#0_pre})/" \
		-e "s/^set(BUILD_COMMIT \"unknown\")$/set(BUILD_COMMIT \"${MY_COMMIT:0:7}\")/" \
		cmake/build-info.cmake || die
}

src_configure() {
	local mycmakeargs=(
		-DCMAKE_SKIP_BUILD_RPATH=ON
		-DGGML_CCACHE=OFF
		-DLLAMA_BUILD_TESTS=OFF
		-DLLAMA_BUILD_EXAMPLES=ON
		-DLLAMA_BUILD_SERVER=ON
		-DLLAMA_CURL=$(usex curl)

		-DGGML_RPC=ON
		-DGGML_CUDA=$(usex cuda)
		-DGGML_OPENMP=$(usex openmp)
		-DGGML_VULKAN=$(usex vulkan)

		# find_package(NCCL) is automagic here: with USE=cuda it silently links
		# whatever NCCL is lying around, and there is no dependency to express
		# it.  Keep the build reproducible instead.
		-DGGML_NCCL=OFF

		-DGGML_NATIVE=OFF
		-DGGML_AVX=$(usex cpu_flags_x86_avx)
		-DGGML_AVX2=$(usex cpu_flags_x86_avx2)
		-DGGML_AVXVNNI=$(usex cpu_flags_x86_avx_vnni)
		-DGGML_AVX512_VBMI=$(usex cpu_flags_x86_avx512vbmi)
		-DGGML_AVX512_VNNI=$(usex cpu_flags_x86_avx512_vnni)
		-DGGML_AVX512_BF16=$(usex cpu_flags_x86_avx512_bf16)
		-DGGML_FMA=$(usex cpu_flags_x86_fma3)
		-DGGML_F16C=$(usex cpu_flags_x86_f16c)

		# Keep out of the way of sci-ml/llama-cpp, which installs libggml.so and
		# libllama.so under the default libdir.
		-DCMAKE_INSTALL_LIBDIR="${EPREFIX}/usr/$(get_libdir)/ik_llama.cpp"
		-DCMAKE_INSTALL_RPATH="${EPREFIX}/usr/$(get_libdir)/ik_llama.cpp"
	)

	# ggml gates the whole AVX512 foundation behind a single option.
	if use cpu_flags_x86_avx512f &&
		use cpu_flags_x86_avx512cd &&
		use cpu_flags_x86_avx512vl &&
		use cpu_flags_x86_avx512dq &&
		use cpu_flags_x86_avx512bw; then
		mycmakeargs+=( -DGGML_AVX512=ON )
	else
		mycmakeargs+=( -DGGML_AVX512=OFF )
	fi

	if use cuda; then
		local -x CUDAHOSTCXX="$(cuda_gccdir)"
		# tries to recreate dev symlinks
		cuda_add_sandbox
		addpredict "/dev/char/"
	fi

	if use hip; then
		export HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)"
		mycmakeargs+=(
			-DAMDGPU_TARGETS="$(get_amdgpu_flags)"
			# This fork predates the GGML_HIP rename; the option it actually
			# reads is GGML_HIPBLAS.  -DGGML_HIP=ON is silently ignored.
			-DGGML_HIPBLAS=ON
		)
	fi

	cmake_src_configure
}

src_install() {
	cmake_src_install

	# The headers are the same llama.h/ggml*.h that sci-ml/llama-cpp installs,
	# so this package ships no development files at all.
	rm -r "${ED}/usr/include" || die

	# llama.pc goes to a hardcoded lib/pkgconfig, escaping the isolated libdir
	# set above, and it describes the headers just removed.
	rm -r "${ED}/usr/lib/pkgconfig" || die

	# Every binary is named llama-* upstream, exactly as in sci-ml/llama-cpp.
	local f
	shopt -s nullglob
	for f in "${ED}"/usr/bin/*; do
		mv "${f}" "${ED}/usr/bin/ik_${f##*/}" || die
	done
	shopt -u nullglob
}
