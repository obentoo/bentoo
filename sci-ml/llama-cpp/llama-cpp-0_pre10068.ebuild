# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

ROCM_VERSION="6.3"

inherit cmake cuda rocm linux-info

TINY_LLAMAS_COMMIT="99dd1a73db5a37100bd4ae633f4cfce6560e1567"

DESCRIPTION="LLM inference in C/C++"
HOMEPAGE="https://github.com/ggml-org/llama.cpp"

if [[ ${PV} == *9999* ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/ggml-org/llama.cpp.git"
else
	MY_PV="b${PV#0_pre}"
	SRC_URI="
		https://github.com/ggml-org/llama.cpp/archive/refs/tags/${MY_PV}.tar.gz -> ${P}.tar.gz
		webui? (
			https://github.com/ggml-org/llama.cpp/releases/download/${MY_PV}/llama-${MY_PV}-ui.tar.gz -> ${P}-ui.tar.gz
		)
	"
	S="${WORKDIR}/llama.cpp-${MY_PV}"
	KEYWORDS="~amd64 ~arm64"
fi

SRC_URI+="
	examples? (
		https://huggingface.co/ggml-org/tiny-llamas/resolve/${TINY_LLAMAS_COMMIT}/stories15M-q4_0.gguf
			-> ggml-org_models_tinyllamas_stories15M-q4_0-${TINY_LLAMAS_COMMIT}.gguf
	)
"

LICENSE="MIT"
SLOT="0"

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

IUSE="openblas +openmp blis rocm cuda opencl vulkan flexiblas wmma examples rpc +server webui ${CPU_FLAGS[*]}"

# The ROCm trio (dev-util/hip, sci-libs/hipBLAS, sci-libs/rocWMMA) is
# ~amd64-only, so arm64? ( !rocm ) makes the combination unselectable and
# portage will refuse it.  pkgcheck nevertheless reports
# NonsolvableDeps{InDev,InStable} for the rocm branch on arm64 profiles.
# Note this is package-specific, not a blanket pkgcheck limitation: the
# sibling sci-ml/whisper-cpp guards hip the same way and scans clean.  Several
# candidate causes were ruled out by experiment (dropping
# rocm? ( ${ROCM_REQUIRED_USE} ), un-nesting the wmma? block, adding an
# explicit arm64? ( !wmma )) — none changed the result.  ::gentoo suppresses
# the equivalent for sci-ml/ggml via profiles/arch/arm64/package.use.mask,
# which an overlay cannot reach: the profile in use comes from ::gentoo and
# does not inherit ours.  Treated as known-benign until bentoo ships its own
# profile tree.  See story 002 design D1.4a.
REQUIRED_USE="
	?? ( openblas blis flexiblas )
	rocm? ( ${ROCM_REQUIRED_USE} )
	wmma? ( rocm )
	webui? ( server )
	arm64? ( !rocm )
	cpu_flags_arm_sve2? ( cpu_flags_arm_sve )
"

CDEPEND="
	dev-libs/openssl
	openmp? ( llvm-runtimes/openmp:= )
	openblas? ( sci-libs/openblas:= )
	blis? ( sci-libs/blis:= )
	flexiblas? ( sci-libs/flexiblas:= )
	rocm? (
		>=dev-util/hip-${ROCM_VERSION}
		>=sci-libs/hipBLAS-${ROCM_VERSION}
		wmma? ( >=sci-libs/rocWMMA-${ROCM_VERSION} )
	)
	cuda? ( dev-util/nvidia-cuda-toolkit:= )
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
BDEPEND="
	vulkan? ( media-libs/shaderc )
"

pkg_setup() {
	if use rocm; then
		linux-info_pkg_setup
		if linux-info_get_any_version && linux_config_exists; then
			if ! linux_chkconfig_present HSA_AMD_SVM; then
				ewarn "To use ROCm/HIP, you need to have HSA_AMD_SVM option enabled in your kernel."
			fi
		fi
	fi
}

src_unpack() {
	if [[ ${PV} == *9999* ]]; then
		git-r3_src_unpack
	else
		default
	fi

	if use webui; then
		if [[ ${PV} == *9999* ]]; then
			# Upstream publishes the prebuilt webui dist only per release
			# tag.  The mutable bucket pointer this used to fetch carries no
			# Manifest checksum, so it cannot be expressed in SRC_URI and
			# cannot be verified; fetching it here would also need
			# RESTRICT="network-sandbox" for an unverifiable input.  Every
			# versioned snapshot carries the dist tarball as a real SRC_URI
			# entry, so use one of those instead.
			die "USE=webui is unsupported on a live ebuild: the webui dist has no verifiable source"
		else
			ln -s "${WORKDIR}/llama-${MY_PV}" "${S}/tools/ui/dist" || die
		fi
	fi
}

src_prepare() {
	use cuda && cuda_src_prepare
	cmake_src_prepare
	if use examples; then
		mkdir -p "${BUILD_DIR}/tinyllamas" || die
		cp "${DISTDIR}/ggml-org_models_tinyllamas_stories15M-q4_0-${TINY_LLAMAS_COMMIT}.gguf" \
			"${BUILD_DIR}/tinyllamas/stories15M-q4_0.gguf" || die
	fi
}

src_configure() {
	if [[ ${PV} == *9999* ]]; then
		local mycmakeargs=(
			-DLLAMA_BUILD_NUMBER="$(git rev-list --count HEAD)"
			-DLLAMA_BUILD_COMMIT="$(git rev-parse HEAD)"
		)
	else
		local mycmakeargs=( -DLLAMA_BUILD_NUMBER="${MY_PV#b}" )
	fi

	mycmakeargs+=(
		-DGGML_CCACHE=OFF
		-DCMAKE_SKIP_BUILD_RPATH=ON
		-DLLAMA_BUILD_TESTS=OFF
		-DLLAMA_BUILD_EXAMPLES="$(usex examples)"
		-DLLAMA_BUILD_SERVER="$(usex server)"
		-DLLAMA_BUILD_UI="$(usex webui)"

		-DGGML_RPC="$(usex rpc)"
		-DGGML_CUDA="$(usex cuda)"
		-DGGML_OPENCL="$(usex opencl)"
		-DGGML_OPENMP="$(usex openmp)"
		-DGGML_VULKAN="$(usex vulkan)"

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

	if use openblas; then
		mycmakeargs+=(
			-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
		)
	fi

	if use blis; then
		mycmakeargs+=(
			-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=FLAME
		)
	fi

	if use flexiblas; then
		mycmakeargs+=(
			-DGGML_BLAS=ON -DGGML_BLAS_VENDOR=FlexiBLAS
		)
	fi

	if use cuda; then
		local -x CUDAHOSTCXX="$(cuda_gccdir)"
		# tries to recreate dev symlinks
		cuda_add_sandbox
		addpredict "/dev/char/"
	fi

	if use rocm; then
		export HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)"
		mycmakeargs+=(
			-DAMDGPU_TARGETS="$(get_amdgpu_flags)"
			-DGGML_HIP=ON
			-DGGML_HIP_ROCWMMA_FATTN="$(usex wmma)"
		)
	fi

	cmake_src_configure
}
