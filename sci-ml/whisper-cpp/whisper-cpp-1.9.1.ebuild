# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit cmake

MY_PN="whisper.cpp"
MY_P="${MY_PN}-${PV}"

DESCRIPTION="Port of OpenAI's Whisper model in C/C++"
HOMEPAGE="https://github.com/ggml-org/whisper.cpp"
SRC_URI="https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v${PV}.tar.gz -> ${MY_P}.tar.gz"

S="${WORKDIR}/${MY_P}"

LICENSE="MIT"
SLOT="0"
KEYWORDS="~amd64 ~arm64"

X86_CPU_FLAGS=(
	sse4_2
	avx
	avx_vnni
	avx2
	bmi2
	avx512f avx512cd avx512vl avx512dq avx512bw
	avx512vbmi
	avx512_vnni
	avx512_bf16
	fma3
	f16c
	amx_tile
	amx_int8
	amx_bf16
)
CPU_FLAGS=( "${X86_CPU_FLAGS[@]/#/cpu_flags_x86_}" )

# ggml exposes no per-feature -DGGML_* option on ARM.  The only lever is
# GGML_CPU_ARM_ARCH, an accumulated -march= string, so these flags are gated at
# compile time via -march tags rather than by individual cmake options.
# ggml SME (armv9.2-a) is deliberately not exposed: it has no cpu_flags_arm_*
# value in profiles/desc/cpu_flags_arm.desc, and forcing armv9.2-a would exclude
# every pre-Armv9 core.  Users who want it set GGML_CPU_ARM_ARCH themselves.
ARM_CPU_FLAGS=( asimddp asimdhp sve i8mm sve2 )
CPU_FLAGS+=( "${ARM_CPU_FLAGS[@]/#/cpu_flags_arm_}" )

IUSE="blas cuda ffmpeg opencl hip sdl2 vulkan ${CPU_FLAGS[*]}"

# The ROCm stack behind USE=rocm (sci-libs/hipBLAS and the dev-util/hip and
# sci-libs/rocBLAS packages it pulls) is ~amd64-only, so arm64? ( !hip ) makes
# the combination unselectable instead of leaving arm64 users with an
# unsatisfiable dependency.  ::gentoo expresses the same thing for sci-ml/ggml
# through profiles/arch/arm64/package.use.mask, which an overlay cannot reach:
# the profile in use comes from ::gentoo and does not inherit ours.
#
# sci-ml/llama-cpp carries the equivalent constraint and still trips
# NonsolvableDeps{InDev,InStable} on arm64 profiles, because pkgcheck's solver
# gives up on its hip? ( ${ROCM_REQUIRED_USE} ) branch.  The simpler constraint
# below is honoured, so this package scans clean; should that ever regress to a
# NonsolvableDeps report it is benign for the same reason it is benign there.
REQUIRED_USE="
	arm64? ( !hip )
	cpu_flags_arm_sve2? ( cpu_flags_arm_sve )
"

CDEPEND="
	blas? ( sci-libs/openblas )
	cuda? ( dev-util/nvidia-cuda-toolkit:= )
	ffmpeg? ( media-video/ffmpeg:= )
	hip? ( sci-libs/hipBLAS:= )
	sdl2? ( media-libs/libsdl2:= )
"
DEPEND="${CDEPEND}
	opencl? ( dev-util/opencl-headers )
	vulkan? (
		dev-util/spirv-headers
		dev-util/vulkan-headers
	)
"
RDEPEND="${CDEPEND}
	opencl? ( dev-libs/opencl-icd-loader )
	vulkan? ( media-libs/vulkan-loader )
"
BDEPEND="vulkan? ( media-libs/shaderc )"

src_configure() {
	# Every ggml artifact has to stay out of the default libdir: sci-ml/llama-cpp
	# vendors the same ggml tree and already owns libggml.so, libggml-base.so,
	# the per-backend libggml-*.so, lib/cmake/ggml/ and pkgconfig/ggml.pc there.
	# whisper.cpp 1.9.x adds libparakeet.so next to libwhisper.so, and both of
	# those key off CMAKE_INSTALL_LIBDIR too, along with their cmake/ and
	# pkgconfig/ files.  Relocating LIBDIR moves the whole set in one shot;
	# RPATH is then required so the /usr/bin/whisper-* binaries still resolve.
	local whisperdir="${EPREFIX}/usr/$(get_libdir)/${MY_PN}"

	local mycmakeargs=(
		-DCMAKE_INSTALL_LIBDIR="${whisperdir}"
		-DCMAKE_INSTALL_RPATH="${whisperdir}"

		-DWHISPER_BUILD_EXAMPLES=ON
		-DWHISPER_BUILD_SERVER=ON
		-DWHISPER_BUILD_TESTS=OFF
		-DGGML_CCACHE=OFF

		-DGGML_BLAS="$(usex blas)"
		-DGGML_CUDA="$(usex cuda)"
		-DGGML_HIP="$(usex hip)"
		-DGGML_OPENCL="$(usex opencl)"
		-DGGML_VULKAN="$(usex vulkan)"
		-DWHISPER_COMMON_FFMPEG="$(usex ffmpeg)"
		-DWHISPER_SDL2="$(usex sdl2)"

		# GGML_NATIVE=OFF alone is not enough: ggml sets INS_ENB=ON whenever
		# GGML_NATIVE is off but GGML_NATIVE_DEFAULT is on, which turns
		# GGML_SSE42/AVX/AVX2/BMI2/FMA/F16C on unconditionally and produces
		# binaries that SIGILL on any host without AVX2.  Every instruction-set
		# option is therefore pinned to the corresponding CPU_FLAGS_X86 value.
		-DGGML_NATIVE=OFF
		-DGGML_SSE42="$(usex cpu_flags_x86_sse4_2)"
		-DGGML_AVX="$(usex cpu_flags_x86_avx)"
		-DGGML_AVX_VNNI="$(usex cpu_flags_x86_avx_vnni)"
		-DGGML_AVX2="$(usex cpu_flags_x86_avx2)"
		-DGGML_BMI2="$(usex cpu_flags_x86_bmi2)"
		-DGGML_AVX512_VBMI="$(usex cpu_flags_x86_avx512vbmi)"
		-DGGML_AVX512_VNNI="$(usex cpu_flags_x86_avx512_vnni)"
		-DGGML_AVX512_BF16="$(usex cpu_flags_x86_avx512_bf16)"
		-DGGML_FMA="$(usex cpu_flags_x86_fma3)"
		-DGGML_F16C="$(usex cpu_flags_x86_f16c)"
		-DGGML_AMX_TILE="$(usex cpu_flags_x86_amx_tile)"
		-DGGML_AMX_INT8="$(usex cpu_flags_x86_amx_int8)"
		-DGGML_AMX_BF16="$(usex cpu_flags_x86_amx_bf16)"
	)

	if use cpu_flags_x86_avx512f &&
		use cpu_flags_x86_avx512cd &&
		use cpu_flags_x86_avx512vl &&
		use cpu_flags_x86_avx512dq &&
		use cpu_flags_x86_avx512bw; then
		mycmakeargs+=( -DGGML_AVX512=ON )
	else
		mycmakeargs+=( -DGGML_AVX512=OFF )
	fi

	if use arm64; then
		# Mirrors upstream's escalation table in ggml/src/ggml-cpu/CMakeLists.txt:
		# each feature bumps the baseline to the first architecture level that
		# supported it, and the tags accumulate.  Order is load-bearing —
		# last write wins, so the highest required level ends up in arm_arch.
		# Setting GGML_CPU_ARM_ARCH bypasses that table entirely (it is the
		# first branch of an if/elseif), which is why it is replicated here.
		local arm_arch="armv8-a" arm_tags=""
		if use cpu_flags_arm_asimddp; then arm_arch="armv8.2-a"; arm_tags+="+dotprod"; fi
		if use cpu_flags_arm_asimdhp; then arm_arch="armv8.2-a"; arm_tags+="+fp16";    fi
		if use cpu_flags_arm_sve;     then arm_arch="armv8.2-a"; arm_tags+="+sve";     fi
		if use cpu_flags_arm_i8mm;    then arm_arch="armv8.6-a"; arm_tags+="+i8mm";    fi
		if use cpu_flags_arm_sve2;    then arm_arch="armv8.6-a"; arm_tags+="+sve2";    fi
		mycmakeargs+=( -DGGML_CPU_ARM_ARCH="${arm_arch}${arm_tags}" )
	fi

	if use blas; then
		# ggml-blas calls cblas_sgemm; without an explicit vendor, CMake's
		# FindBLAS picks the Fortran-only libblas.so and the link dies on
		# undefined cblas_sgemm. openblas (already a dep) ships cblas.
		mycmakeargs+=( -DGGML_BLAS_VENDOR=OpenBLAS )
	fi

	if use cuda; then
		# CUDA 13.x nvcc rejects gcc > 15, so pin the host compiler when a
		# matching gcc-15 is installed.  Derived from ${CHOST} instead of a
		# hardcoded x86_64-pc-linux-gnu path, which could never match on arm64
		# and silently skipped the pin there.
		local cuda_host_cxx="${BROOT}/usr/bin/${CHOST}-g++-15"
		if [[ -x ${cuda_host_cxx} ]]; then
			mycmakeargs+=( -DCMAKE_CUDA_HOST_COMPILER="${cuda_host_cxx}" )
		fi
	fi

	cmake_src_configure
}

src_install() {
	cmake_src_install

	# The ggml, whisper and parakeet public headers are installed through cmake's
	# PUBLIC_HEADER property, which keys off CMAKE_INSTALL_INCLUDEDIR and is not
	# covered by the libdir relocation in src_configure.  sci-ml/llama-cpp
	# already owns /usr/include/ggml*.h and /usr/include/gguf.h, so drop the
	# whole tree: this package ships applications, not a development target.
	rm -rf "${ED}/usr/include" || die

	newinitd "${FILESDIR}/${PN}.init" "${PN}"
	newconfd "${FILESDIR}/${PN}.confd" "${PN}"
}
