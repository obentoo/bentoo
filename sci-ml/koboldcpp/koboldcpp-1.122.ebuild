# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

ROCM_VERSION="6.3"
PYTHON_COMPAT=( python3_{12..14} )

inherit cuda python-single-r1 rocm toolchain-funcs wrapper

DESCRIPTION="All-in-one local AI server (LLM, image, speech, TTS) on ggml/llama.cpp"
HOMEPAGE="https://github.com/LostRuins/koboldcpp"
SRC_URI="https://github.com/LostRuins/${PN}/archive/refs/tags/v${PV}.tar.gz -> ${P}.gh.tar.gz"
S="${WORKDIR}/${PN}-${PV}"

# AGPL-3.0 covers the koboldcpp code + the embedded KoboldAI Lite UI; the
# bundled ggml / llama.cpp / stable-diffusion.cpp / TTS.cpp libraries are MIT
# (MIT_LICENSE_GGML_SDCPP_LLAMACPP_ONLY.md).
LICENSE="AGPL-3+ MIT"
SLOT="0"
# arm64 is technically clean here, and deliberately NOT keyworded yet.
#
# The source evidence is good: the Makefile's -march=native/-mtune=native block
# sits inside the "ifeq ($(UNAME_M),x86_64 i686 amd64)" guard, the aarch64 block
# adds nothing at all under LLAMA_PORTABLE (Makefile lines 355-376), and ggml
# carries NEON kernels for the aarch64 baseline. Only koboldcpp_default is built
# there: the failsafe/noavx2 variants are x86-only by construction (FAILSAFE_BUILD
# and NOAVX2_BUILD are defined only inside the same x86 guard).
#
# But no arm64 build of this ebuild has ever been run, and that is the same
# position the other four ggml packages were in when story 002 stripped their
# ~arm64 on 2026-08-08: shipping an unvalidated keyword is worse than shipping
# none, because it tells an arm64 user the package was considered when it was
# only assumed. sci-ml/{llama-cpp,whisper-cpp,stable-diffusion-cpp,ik_llama-cpp}
# are all ~amd64 today; keywording this one ~arm64 on source reading alone would
# make it the odd member of a family whose policy was settled against exactly
# that. Story 003 R1.1 asked for ~arm64; the later decision in 002 overrides it.
#
# The arm64 machinery below (arm64? ( !rocm ), the aarch64 branch in src_compile)
# is kept intact on purpose, so restoring the keyword is a one-line change once a
# real arm64 build is recorded — chroot, hardware, or a native runner.
KEYWORDS="~amd64"

# Every acceleration backend upstream ships is exposed as an optional flag;
# none is required, and a CPU-only build is the default minus USE=vulkan.
# Vulkan is upstream's officially supported GPU path for both AMD and NVIDIA
# and is the cheapest to satisfy, so it stays enabled by default.
#
# cuda (koboldcpp_cublas) and rocm (koboldcpp_hipblas) are upstream targets in
# the Makefile's own default target list.  They are wired here and have NOT
# been build-verified on this overlay's build host -- "not verified on the
# maintainer's hardware" is not a reason to withhold a backend, so the
# verification status is recorded rather than the backend dropped.
IUSE="cuda rocm +vulkan"

# ISA selection for the x86 CPU backend.  Upstream's Makefile has exactly
# three x86 tiers under LLAMA_PORTABLE, selected by LLAMA_NOAVX1/LLAMA_NOAVX2:
#
#   (neither)        -mavx2 -mavx -mfma -mf16c -msse3 -mssse3
#   LLAMA_NOAVX2=1   -mavx -msse3 -mssse3
#   LLAMA_NOAVX1=1   -msse3 -mssse3
#
# so cpu_flags_x86_f16c and cpu_flags_x86_fma3 have no tier of their own: they
# only qualify the AVX2 tier, which is why REQUIRED_USE ties them to avx2
# instead of letting the ebuild silently pick a lower tier.
IUSE+=" cpu_flags_x86_avx cpu_flags_x86_avx2 cpu_flags_x86_f16c cpu_flags_x86_fma3"

# The ROCm stack behind USE=rocm (dev-util/hip, sci-libs/hipBLAS) is
# ~amd64-only, so arm64? ( !rocm ) makes the combination unselectable instead
# of leaving arm64 users with an unsatisfiable dependency.
REQUIRED_USE="
	${PYTHON_REQUIRED_USE}
	rocm? ( ${ROCM_REQUIRED_USE} )
	arm64? ( !rocm )
	cpu_flags_x86_avx2? ( cpu_flags_x86_avx cpu_flags_x86_f16c cpu_flags_x86_fma3 )
"

# koboldcpp.py is a pure-stdlib launcher that dlopen()s the compiled backend
# .so files; the image/speech/TTS features all live in the C++ libraries, so
# there are no third-party Python runtime dependencies.
RDEPEND="
	${PYTHON_DEPS}
	cuda? ( dev-util/nvidia-cuda-toolkit:= )
	rocm? (
		>=dev-util/hip-${ROCM_VERSION}
		>=sci-libs/hipBLAS-${ROCM_VERSION}
	)
	vulkan? ( media-libs/vulkan-loader )
"
DEPEND="
	${RDEPEND}
	vulkan? ( dev-util/vulkan-headers )
"
BDEPEND="
	${PYTHON_DEPS}
	vulkan? ( media-libs/shaderc )
"

# Windows-only helpers plus one stray x86-64 ELF, none of which this ebuild
# builds, runs or installs.  They are deleted in src_prepare so the property
# "no executable blob ships in the image" is enforced at the source, not left
# to the install file list.  Absence of any of them is a hard error: the
# tarball is Manifest-pinned, so a missing entry can only mean the ebuild was
# copied to a version whose contents were never checked.
KCPP_BLOBS=(
	aria2c-win.exe
	cudart64_110.dll
	cudart64_12.dll
	glslc-linux
	glslc.exe
	simplecpuinfo
	simplecpuinfo.exe
)

pkg_setup() {
	python-single-r1_pkg_setup
}

src_prepare() {
	default

	# cuda.eclass EXPORT_FUNCTIONS src_prepare, and defining src_prepare here
	# overrides it -- so cuda_sanitize only runs if called explicitly. Gate it
	# on the flag: cuda_sanitize resolves cuda_gccdir, which dies with
	# "cuda-config not found" when no toolkit is installed, and that would
	# break the build for every user without CUDA. sci-ml/sherpa-onnx hit
	# exactly that in the merge gate on 2026-08-16 by not defining src_prepare
	# at all and inheriting the eclass one unguarded.
	#
	# Without this call the USE=cuda build passes unsanitized NVCCFLAGS
	# straight to nvcc.
	use cuda && cuda_src_prepare

	# The release build strips the .so at link time (-s); leave stripping
	# to Portage so splitdebug/nostrip are honored and the pre-stripped QA
	# notice is silenced. Keep -DNDEBUG (it no-ops assert()).
	grep -q -- '-DNDEBUG -s' Makefile ||
		die "strip-deferral anchor '-DNDEBUG -s' is gone from Makefile"
	sed -i -e 's/-DNDEBUG -s/-DNDEBUG/g' Makefile || die

	# Dropping glslc-linux/glslc.exe also makes the Vulkan build use the
	# system media-libs/shaderc glslc (LLAMA_USE_BUNDLED_GLSLC= empty in
	# src_compile selects it first, then falls back to ./glslc-linux).
	local blob
	for blob in "${KCPP_BLOBS[@]}"; do
		[[ -f ${blob} ]] || die "expected prebuilt blob ${blob} not found; re-audit the tarball"
	done
	rm -f "${KCPP_BLOBS[@]}" || die
}

src_compile() {
	tc-export CC CXX

	# LLAMA_PORTABLE=1 is what keeps the build independent of the build
	# host.  Without it the Makefile appends -march=native -mtune=native to
	# CFLAGS on x86 and -mcpu=native on aarch64, tuning koboldcpp_default.so
	# to whatever machine happened to compile it.
	#
	# LLAMA_USE_BUNDLED_GLSLC must be empty (not 0): the Makefile tests it
	# with [ -n "$LLAMA_USE_BUNDLED_GLSLC" ], so any value at all selects
	# the bundled shader compiler that src_prepare just deleted.
	#
	# Note that upstream assigns CFLAGS/CXXFLAGS/LDFLAGS itself rather than
	# appending to the environment, and the include paths it needs travel in
	# those same variables -- overriding them on the make command line would
	# break the build.  User *FLAGS therefore do not reach this build; the
	# ISA is chosen through cpu_flags_x86_* below instead.
	local makeargs=(
		LLAMA_PORTABLE=1
		LLAMA_USE_BUNDLED_GLSLC=
	)

	if use amd64 || use x86; then
		if use cpu_flags_x86_avx2; then
			# Highest tier: AVX2 + FMA + F16C, tied together by
			# REQUIRED_USE.
			:
		elif use cpu_flags_x86_avx; then
			makeargs+=( LLAMA_NOAVX2=1 )
		else
			makeargs+=( LLAMA_NOAVX1=1 )
		fi
	fi

	# koboldcpp_default and koboldcpp_vulkan share the same object flags and
	# are what upstream's own default target builds together.
	local targets=( koboldcpp_default )
	if use vulkan; then
		targets+=( koboldcpp_vulkan )
		makeargs+=( LLAMA_VULKAN=1 )
	fi

	emake "${makeargs[@]}" "${targets[@]}"

	# CUDA and HIP get their own make runs on purpose: both define rules for
	# ggml-cuda.o and ggml/src/ggml-cuda/%.o, so defining LLAMA_CUBLAS and
	# LLAMA_HIPBLAS in one invocation makes the HIP recipes silently
	# override the CUDA ones.  Objects shared with the run above are reused
	# as-is, exactly as upstream's default target does.
	if use cuda; then
		# Under LLAMA_PORTABLE nvcc is invoked with -arch=all, i.e. every
		# GPU architecture the installed toolkit supports, rather than
		# -arch=native.  That is slow to build and deliberate: it is the
		# only setting that produces a binary usable on a machine other
		# than the one that compiled it, legacy NVIDIA generations
		# included.
		cuda_add_sandbox
		addpredict /dev/char/
		emake "${makeargs[@]}" \
			LLAMA_CUBLAS=1 \
			LLAMA_CUDA_CCBIN="$(cuda_gccdir)" \
			koboldcpp_cublas
	fi

	if use rocm; then
		# ROCM_PATH, HCC and HCXX are passed explicitly because the
		# Makefile picks its toolchain paths from $(wildcard /opt/rocm)
		# rather than from ROCM_PATH: on a host that also has
		# /opt/rocm (a therock-bin install, say) it would look for
		# clang++ under the wrong prefix.
		#
		# GPU_TARGETS likewise: the Makefile's own default appends
		# $(shell amdgpu-arch), which reads the build host's GPU.  The
		# AMDGPU_TARGETS USE_EXPAND is the packaging-level answer to the
		# same question and does not depend on what card is plugged in.
		rocm_add_sandbox
		emake "${makeargs[@]}" \
			LLAMA_HIPBLAS=1 \
			ROCM_PATH="$(hipconfig -R)" \
			HCC="$(hipconfig -l)/clang" \
			HCXX="$(hipconfig -l)/clang++" \
			GPU_TARGETS="${AMDGPU_TARGETS}" \
			koboldcpp_hipblas
	fi
}

src_install() {
	local dest="/usr/share/${PN}"

	insinto "${dest}"
	doins koboldcpp.py
	# The compiled backends (koboldcpp_default.so plus whichever of
	# koboldcpp_{vulkan,cublas,hipblas}.so the USE flags selected) sit
	# beside the launcher, which locates them via
	# os.path.dirname(__file__) and picks one at runtime.
	doins koboldcpp_*.so
	# Embedded web UI (KoboldAI Lite), API docs, SD/TTS resources and the
	# chat-format adapters, read from <script_dir>/embd_res and kcpp_adapters.
	doins -r embd_res kcpp_adapters

	python_fix_shebang "${ED}${dest}/koboldcpp.py"

	# Thin launcher on PATH.
	make_wrapper "${PN}" "${EPYTHON} ${EPREFIX}${dest}/koboldcpp.py"

	dodoc README.md
}

pkg_postinst() {
	elog "koboldcpp installed to ${EROOT}/usr/share/${PN}; run it with:"
	elog "    koboldcpp --model /path/to/model.gguf"
	elog
	if use vulkan; then
		elog "Vulkan (the official AMD/NVIDIA GPU path) is available; add"
		elog "    --usevulkan"
		elog "to offload to the GPU."
	fi
	if use cuda; then
		elog "CUDA is available; add"
		elog "    --usecublas"
		elog "to offload to an NVIDIA GPU."
	fi
	if use rocm; then
		elog "ROCm/hipBLAS is available; add"
		elog "    --usecublas"
		elog "to offload to an AMD GPU (koboldcpp reuses the cuBLAS flag"
		elog "for the hipBLAS backend)."
	fi
	elog "Models are NOT bundled; download a .gguf yourself."
}
