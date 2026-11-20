# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{12..15} )

inherit cmake cuda flag-o-matic python-single-r1 toolchain-funcs

DESCRIPTION="Speech-to-text, TTS, speaker diarization etc. using onnxruntime"
HOMEPAGE="
	https://k2-fsa.github.io/sherpa/onnx/
	https://github.com/k2-fsa/sherpa-onnx
"

# THE OVERLAY'S REFERENCE ANSWER TO CMake FetchContent.
#
# Upstream's build declares every vendored dependency through FetchContent,
# which fetches at *configure* time — inside the sandbox, with no network. The
# defeat is not a patch: each of upstream's cmake/*.cmake modules checks a
# `possible_file_locations` list before reaching for the network, and that list
# includes ${CMAKE_SOURCE_DIR}. So the archives are declared here in SRC_URI,
# left archived, and copied into ${S} by src_unpack; configure then finds them
# locally and never opens a socket.
#
# Three properties make this work, and all three are load-bearing:
#   - The filenames must match what the cmake modules look for, which is why
#     every entry carries an explicit `->` rename. A renamed-wrong distfile is
#     not an error, it is a silent fallback to the network.
#   - .zip stays .zip. Upstream ships kissfft, websocketpp, piper-phonemize and
#     espeak-ng as .zip and its modules name them that way; converting to
#     .tar.gz would miss the fallback. This is what BDEPEND=app-arch/unzip is
#     for — CMake extracts them at configure time.
#
#     pkgcheck reports TarballAvailable on those four, suggesting the .tar.gz
#     equivalents. DO NOT act on it: it is a false positive here, and acting on
#     it silently restores the network fetch this whole block exists to remove.
#     Verified against the 1.13.5 sources — cmake/websocketpp.cmake,
#     cmake/piper-phonemize.cmake and cmake/espeak-ng-for-piper.cmake each build
#     a `possible_file_locations` list containing the literal .zip filename
#     under ${CMAKE_SOURCE_DIR} and fall through to `_URL` (the network) when no
#     entry EXISTS. The name is matched verbatim; a .tar.gz sitting beside it
#     does not satisfy the check. kissfft has no module of its own — it is
#     pulled by cmake/kaldi-native-fbank.cmake through the same mechanism.
#   - Sub-dependencies resolve through the same global ${CMAKE_SOURCE_DIR}
#     fallback (kissfft is pulled by kaldi-native-fbank, kaldifst by
#     kaldi-decoder), so one staging directory covers the whole tree.
#
# Every entry is pinned by tag or by full commit SHA. Do not relax one to a
# branch: FetchContent would then resolve to whatever HEAD happens to be.
SRC_URI="
	https://github.com/k2-fsa/sherpa-onnx/archive/refs/tags/v${PV}.tar.gz
		-> ${P}.gh.tar.gz
	https://gitlab.com/libeigen/eigen/-/archive/5.0.1/eigen-5.0.1.tar.gz
	https://github.com/likle/cargs/archive/refs/tags/v1.0.3.tar.gz
		-> cargs-1.0.3.tar.gz
	https://github.com/csukuangfj/hclust-cpp/archive/refs/tags/2026-02-25.tar.gz
		-> hclust-cpp-2026-02-25.tar.gz
	https://github.com/nlohmann/json/archive/refs/tags/v3.12.0.tar.gz
		-> json-3.12.0.tar.gz
	https://github.com/k2-fsa/kaldi-decoder/archive/refs/tags/v0.3.0.tar.gz
		-> kaldi-decoder-0.3.0.tar.gz
	https://github.com/csukuangfj/kaldi-native-fbank/archive/refs/tags/v1.22.3.tar.gz
		-> kaldi-native-fbank-1.22.3.tar.gz
	https://github.com/csukuangfj/openfst/archive/refs/tags/v1.8.5-2026-07-09.tar.gz
		-> openfst-1.8.5-2026-07-09.tar.gz
	https://github.com/pkufool/simple-sentencepiece/archive/refs/tags/v0.7.tar.gz
		-> simple-sentencepiece-0.7.tar.gz
	https://github.com/mborgerding/kissfft/archive/febd4caeed32e33ad8b2e0bb5ea77542c40f18ec.zip
		-> kissfft-febd4caeed32e33ad8b2e0bb5ea77542c40f18ec.zip
	https://github.com/k2-fsa/kaldifst/archive/refs/tags/v1.8.0.tar.gz
		-> kaldifst-1.8.0.tar.gz
	portaudio? (
		https://files.portaudio.com/archives/pa_stable_v190700_20210406.tgz
	)
	python? (
		https://github.com/pybind/pybind11/archive/refs/tags/v3.0.0.tar.gz
			-> pybind11-3.0.0.tar.gz
	)
	tts? (
		https://github.com/csukuangfj/espeak-ng/archive/ed530aa113046142eb5115cf2fc9157854d0ffe1.zip
			-> espeak-ng-ed530aa113046142eb5115cf2fc9157854d0ffe1.zip
		https://github.com/csukuangfj/piper-phonemize/archive/f3ff95afc03640bc1399e113e83361192a2fafb4.zip
			-> piper-phonemize-f3ff95afc03640bc1399e113e83361192a2fafb4.zip
	)
	websocket? (
		https://github.com/chriskohlhoff/asio/archive/refs/tags/asio-1-24-0.tar.gz
			-> asio-asio-1-24-0.tar.gz
		https://github.com/zaphoyd/websocketpp/archive/b9aeec6eaf3d5610503439b4fae3581d9aff08e8.zip
			-> websocketpp-b9aeec6eaf3d5610503439b4fae3581d9aff08e8.zip
	)
"

LICENSE="Apache-2.0"
SLOT="0"
# arm64 is deliberately not keyworded, and the omission is not about upstream.
#
# Upstream does publish aarch64 and armv7l wheels, which is real evidence and
# would normally be enough under this overlay's arm64 policy. But the ebuild's
# own build path has never been exercised on arm64: it compiles a large C++
# tree plus eleven vendored dependencies, and it links against
# sci-libs/onnxruntime, which is itself ~amd64 here. Keywording ~arm64 would
# assert an arm64 build nobody has run, against a dependency that has no arm64
# keyword to satisfy it.
#
# This matches the decision taken across the ggml family on 2026-08-08 and
# 2026-08-16: sci-ml/{llama-cpp,whisper-cpp,stable-diffusion-cpp,ik_llama-cpp,
# koboldcpp} are all ~amd64 for the same reason.
#
# Restore ~arm64 when sci-libs/onnxruntime carries it AND a recorded arm64
# build of this package exists. Upstream wheels alone are not the missing
# piece; they were never in doubt.
KEYWORDS="~amd64"
IUSE="cuda +portaudio +python +tts +websocket"
REQUIRED_USE="python? ( ${PYTHON_REQUIRED_USE} )"

# sherpa-onnx vendors and statically links portaudio (PA_BUILD_STATIC=ON in
# cmake/portaudio.cmake), so USE=portaudio adds no system dependency — it only
# toggles whether the mic-recording demo CLIs get built. media-libs/alsa-lib
# *is* needed regardless: several *-alsa demo binaries link -lasound
# unconditionally.
#
# The blocker against -bin is not currently reciprocated, because bentoo does
# not carry sci-ml/sherpa-onnx-bin (see the note above src_install). Should one
# ever be added, it MUST declare the mirror blocker in the same commit: the
# sci-libs/onnxruntime{,-bin} pair shipped without one, shared 26 installed
# paths, and only failed at the end of a 266 MB build.
RDEPEND="
	!sci-ml/sherpa-onnx-bin
	sci-libs/onnxruntime:=
	media-libs/alsa-lib
	cuda? ( dev-util/nvidia-cuda-toolkit:= )
	python? (
		${PYTHON_DEPS}
	)
"
DEPEND="${RDEPEND}"
# app-arch/unzip is required at build time: CMake extracts the .zip-archived
# vendored deps (kissfft, websocketpp, piper-phonemize, espeak-ng) during
# configure. See the SRC_URI comment for why they stay .zip.
BDEPEND="
	app-arch/unzip
	python? (
		${PYTHON_DEPS}
		$(python_gen_cond_dep '
			dev-python/pybind11[${PYTHON_USEDEP}]
		')
	)
"

# NO QA_PREBUILT HERE, DELIBERATELY.
#
# The adopted ebuild set QA_PREBUILT="opt/sherpa-onnx/lib/*" and justified it
# as covering "prebuilt" libraries. That description is wrong: everything under
# /opt/sherpa-onnx/lib is compiled by this ebuild from the sources staged in
# src_unpack — the vendored .a and private .so files are build products, not
# vendor blobs. QA_PREBUILT suppresses exactly the checks that should run on
# freshly built code (stripping, RPATH, unresolved symbols), so setting it
# would hide real defects in output this ebuild is responsible for.
#
# If a future version genuinely ships a prebuilt blob, scope QA_PREBUILT to
# that one path and say which file and why — never to the whole lib directory.

src_unpack() {
	# Only the main tarball is unpacked. The vendored dependency archives stay
	# archived and are copied into ${S}, where the cmake modules'
	# possible_file_locations check finds them. See the SRC_URI comment.
	unpack "${P}.gh.tar.gz"

	# ${A} is a space-separated string of distfile names, not an array.
	local f
	for f in ${A}; do
		[[ ${f} == "${P}.gh.tar.gz" ]] && continue
		cp -- "${DISTDIR}/${f}" "${S}/" || die "failed staging ${f} into ${S}"
	done
}

src_prepare() {
	# MUST be defined, even though it looks like boilerplate.
	#
	# cuda.eclass does `EXPORT_FUNCTIONS src_prepare`, and its cuda_src_prepare
	# calls cuda_sanitize unconditionally -- which resolves cuda_gccdir, which
	# dies with "cuda-config not found" when the CUDA toolkit is absent. With
	# no src_prepare of its own, this ebuild inherited that one and failed in
	# the prepare phase for EVERY user without CUDA installed, including
	# USE=-cuda. Caught by the merge gate on 2026-08-16; pkgcheck cannot see it.
	#
	# cmake_src_prepare, not `default`: the cmake eclass tracks state here that
	# cmake_src_configure later depends on.
	cmake_src_prepare
	use cuda && cuda_src_prepare
}

src_configure() {
	use python && python_setup

	# Keep the build directory out of the installed binaries.
	#
	# Upstream puts __FILE__ in its message macros, so the sandbox path is not
	# merely debug metadata — it is printed AT THE USER. `sherpa-onnx --help`
	# opened with
	#   /var/tmp/portage/sci-ml/sherpa-onnx-1.13.5/work/.../parse-options.cc:415
	# before this, and 113 such paths were baked into the installed files.
	#
	# Map ${WORKDIR}, not ${S}: the vendored dependencies are configured under
	# ${S}_build/_deps (kaldi_decoder-src and friends) and leak their own paths,
	# so remapping only the source tree would clear about half of them.
	#
	# -ffile-prefix-map covers __FILE__, __BASE_FILE__ and the debug records in
	# one flag; -fdebug-prefix-map would leave the user-visible strings alone,
	# which are the ones that matter here. The target path follows Gentoo's
	# split-debug convention so a debugger still resolves sources when
	# FEATURES=splitdebug installs them.
	append-flags -ffile-prefix-map="${WORKDIR}=/usr/src/debug/${CATEGORY}/${PF}"

	local mycmakeargs=(
		# Self-contained install under /opt keeps the ~23 CLI tools and the
		# vendored helper libraries (cargs etc.) out of /usr/{bin,lib}.
		-DCMAKE_INSTALL_PREFIX="${EPREFIX}/opt/sherpa-onnx"
		-DBUILD_SHARED_LIBS=ON
		# This is what makes the package link bentoo's sci-libs/onnxruntime
		# instead of downloading and bundling its own copy. It is the reason
		# story 002 had to land onnxruntime before this package could exist.
		-DSHERPA_ONNX_USE_PRE_INSTALLED_ONNXRUNTIME_IF_AVAILABLE=ON
		-DSHERPA_ONNX_ENABLE_C_API=ON
		-DSHERPA_ONNX_ENABLE_BINARY=ON
		-DSHERPA_ONNX_ENABLE_SPEAKER_DIARIZATION=ON
		-DSHERPA_ONNX_LINK_LIBSTDCPP_STATICALLY=OFF
		-DSHERPA_ONNX_ENABLE_TESTS=OFF
		-DSHERPA_ONNX_ENABLE_PYTHON=$(usex python)
		-DSHERPA_ONNX_ENABLE_PORTAUDIO=$(usex portaudio)
		-DSHERPA_ONNX_ENABLE_WEBSOCKET=$(usex websocket)
		-DSHERPA_ONNX_ENABLE_TTS=$(usex tts)
		-DSHERPA_ONNX_ENABLE_GPU=$(usex cuda)
		-DSHERPA_ONNX_ENABLE_JNI=OFF
		-DSHERPA_ONNX_ENABLE_WASM=OFF
	)

	if use cuda; then
		# nvcc refuses a host compiler newer than the toolkit supports. The
		# adopted ebuild hardcoded /usr/bin/g++-15, which is wrong twice: it
		# names a bare path that does not exist on a ${CHOST}-prefixed
		# toolchain, and it pins a version that goes stale at the next toolkit
		# bump. cuda_gccdir asks the installed toolkit which GCC slots it
		# accepts and returns the newest acceptable one.
		export CUDAHOSTCXX="$(cuda_gccdir)/${CHOST}-g++"
		[[ -x ${CUDAHOSTCXX} ]] || die "CUDAHOSTCXX=${CUDAHOSTCXX} is not executable"
		cuda_add_sandbox
	fi

	cmake_src_configure
}

src_install() {
	cmake_src_install

	# Put /opt/sherpa-onnx/bin on PATH and its lib on LDPATH so the unprefixed
	# `sherpa-onnx` command works and the libraries resolve transparently.
	newenvd - 99sherpa-onnx <<-EOF
		PATH="${EPREFIX}/opt/sherpa-onnx/bin"
		LDPATH="${EPREFIX}/opt/sherpa-onnx/lib"
	EOF

	if use python; then
		# The bindings must land in site-packages so `import sherpa_onnx`
		# works without PYTHONPATH gymnastics. The pybind11 module dlopens
		# libsherpa-onnx-c-api.so and friends, which the env.d LDPATH above
		# makes reachable.
		local opt_pylib="${ED}/opt/sherpa-onnx/lib"

		# python_get_sitedir already carries ${EPREFIX}: it is computed from
		# base="${EPREFIX}/usr". It must therefore be joined with ${D}, never
		# with ${ED} (which is itself ${D}${EPREFIX}) and never passed to
		# dodir, which prepends ${ED}. The adopted ebuild did both, yielding
		# ${D}${EPREFIX}${EPREFIX}/usr/... — a doubled prefix that is invisible
		# on a normal install, where EPREFIX is empty, and misplaces every
		# binding under Prefix.
		local pylib_dst="${D}$(python_get_sitedir)/sherpa_onnx/lib"
		mkdir -p "${pylib_dst}" || die

		local so found=0
		for so in "${opt_pylib}"/_sherpa_onnx*.so; do
			[[ -e ${so} ]] || continue
			mv "${so}" "${pylib_dst}/" || die
			found=1
		done
		# Fail loudly rather than shipping bindings that cannot import: an
		# upstream rename of the extension module would otherwise pass here
		# and only surface as ImportError on the user's machine.
		[[ ${found} == 1 ]] ||
			die "no _sherpa_onnx*.so found in ${opt_pylib}; upstream may have renamed the extension module"

		python_moduleinto sherpa_onnx
		python_domodule "${S}/sherpa-onnx/python/sherpa_onnx"/*.py
	fi
}

pkg_postinst() {
	elog ""
	elog "sherpa-onnx ${PV} installed to /opt/sherpa-onnx."
	elog "After re-sourcing /etc/profile (new shell or 'source /etc/profile')"
	elog "these are on PATH:"
	elog "  sherpa-onnx --help                    # generic ASR/runtime entry"
	elog "  sherpa-onnx-offline-speaker-diarization --help"
	elog "  sherpa-onnx-vad --help                # voice activity detection"
	elog "  ... (~23 task-specific tools under /opt/sherpa-onnx/bin/)"
	elog ""
	elog "Model files are not bundled — see"
	elog "  https://k2-fsa.github.io/sherpa/onnx/pretrained_models/"
	elog "For speaker diarization specifically, the ONNX-converted pyannote"
	elog "models and 3D-Speaker embeddings live at"
	elog "  https://huggingface.co/csukuangfj/sherpa-onnx-pyannote-segmentation-3-0"
	elog "(ungated, no HuggingFace token required, unlike sci-ml/pyannote-audio)."
	elog ""
}
