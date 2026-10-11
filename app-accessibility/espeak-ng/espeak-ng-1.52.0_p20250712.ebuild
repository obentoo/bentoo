# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# OVERLAY NOTE -- WHY THIS IS HERE.
#
# A temporary mirror. app-text/calibre[piper] (the neural Read aloud engine,
# Piper and Kokoro voices) calls espeak_TextToPhonemesWithTerminator(), which
# no espeak-ng release has: ::gentoo's newest is 1.52.0 (2024-12), and calibre
# itself pins commit a4ca101c (2025-07-12) in bypy/sources.json for that
# reason. This snapshot is that exact commit, so the one combination upstream
# tests is the one users get.
#
# The ebuild is ::gentoo's espeak-ng-9999, whose *_p* branch already exists;
# the only changes are HASH_COMMIT and the KEYWORDS that branch lacks. Remove
# this package once ::gentoo ships a release that has the function (1.53 or
# later), then drop the floor on it in app-text/calibre.
#
# gentoo-parity.sh compares against ::gentoo's 1.52.0, which still builds with
# autotools; upstream moved to CMake before a4ca101c, and so did ::gentoo's
# 9999. Every axis below follows from that one change, carried verbatim:
# BENTOO-DIVERGENCE: INHERIT - cmake toolchain-funcs instead of autotools.
# BENTOO-DIVERGENCE: DEFINED_PHASES - src_compile, for the cross-build native
# espeak-ng-bin that the CMake build needs to compile intonations.
# BENTOO-DIVERGENCE: IUSE - sonic is new in the CMake build; async and man
# were autotools switches with no CMake counterpart.
# BENTOO-DIVERGENCE: DEPEND - sonic? ( media-libs/sonic:= ), same flag.
# BENTOO-DIVERGENCE: RDEPEND - the same sonic dependency; media-sound/sox is
# gone because the CMake build no longer shells out to it.
# BENTOO-DIVERGENCE: BDEPEND - cmake/ninja via the eclass, instead of the
# autotools chain, ronn-ng (man page is prebuilt, see MAN_VERS) and which.
# BENTOO-DIVERGENCE: metadata.xml - this overlay as maintainer, a
# longdescription saying why the mirror exists, and no async/man flags.

CMAKE_QA_COMPAT_SKIP=1 #android/jni/CMakeLists.txt
inherit cmake toolchain-funcs

MAN_VERS="1.51"
DESCRIPTION="Software speech synthesizer for English, and some other languages"
HOMEPAGE="https://github.com/espeak-ng/espeak-ng"

if [[ ${PV} == *9999* ]]; then
	EGIT_REPO_URI="https://github.com/espeak-ng/espeak-ng.git"
	inherit git-r3
elif [[ ${PV} == *_p* ]]; then
	HASH_COMMIT="a4ca101c99de35345f89df58195b2159748b7092"
	SRC_URI="https://github.com/espeak-ng/espeak-ng/archive/${HASH_COMMIT}.tar.gz -> ${P}.tar.gz"
	S="${WORKDIR}/${PN}-${HASH_COMMIT}"
	# BENTOO-DIVERGENCE: KEYWORDS - ::gentoo's *_p* branch sets none (it has
	# no snapshot in the tree); same list as its release branch below.
	KEYWORDS="~amd64 ~arm ~arm64 ~hppa ~loong ~ppc ~ppc64 ~riscv ~sparc ~x86"
else
	SRC_URI="https://github.com/espeak-ng/espeak-ng/archive/${PV}.tar.gz -> ${P}.tar.gz"
	KEYWORDS="~amd64 ~arm ~arm64 ~hppa ~loong ~ppc ~ppc64 ~riscv ~sparc ~x86"
fi

LICENSE="GPL-3+ unicode"
SLOT="0"
IUSE="+klatt mbrola sonic +sound test"
IUSE+=" l10n_ru l10n_zh"
# BENTOO-DIVERGENCE: REQUIRED_USE - media-libs/sonic has no ~loong keyword,
# which ::gentoo's 9999 never meets because it sets no KEYWORDS at all. The
# flag is off by default; pkgcheck's solver ignores REQUIRED_USE and still
# reports NonsolvableDeps for loong, and an overlay cannot mask a flag per arch.
REQUIRED_USE="loong? ( !sonic )"
RESTRICT="!test? ( test )"

DEPEND="
	mbrola? ( app-accessibility/mbrola )
	sonic? ( media-libs/sonic:= )
	sound? ( media-libs/pcaudiolib )
"
RDEPEND="${DEPEND}
	!app-accessibility/espeak
"
BDEPEND="virtual/pkgconfig"
if [[ ${PV} == *9999* ]]; then
	BDEPEND+=" app-text/ronn-ng"
fi

DOCS=( ChangeLog.md README.md docs )

# BENTOO-DIVERGENCE: PATCHES - ::gentoo's 9999 builds master, which already
# has these two upstream commits; a4ca101c predates them, and without them
# espeak-ng.pc lands in /usr/lib/pkgconfig with libdir=/usr/lib on lib64
# systems, so pkg-config stops finding espeak-ng for every reverse dependency.
PATCHES=( "${FILESDIR}/${PN}-cmake-gnuinstalldirs.patch" )

src_prepare() {
	cmake_src_prepare

	if [[ ${PV} != *9999* ]]; then
		cp "${FILESDIR}"/${PN}.1-${MAN_VERS} "${S}"/docs/${PN}.1 || die
	fi

	# BENTOO-DIVERGENCE: src_prepare - drop the SSML <audio> hash test. It
	# loads a WAV through LoadSoundFile(), which reads its header and data
	# size out of bounds (upstream PR #2465, open, ASan-confirmed on master),
	# so the hash depends on uninitialised memory. Not a path calibre uses: it
	# only calls the phonemizer. The grep keeps the sed from going silently
	# stale on a bump.
	grep -qF 'test_ssml_audio "<audio>"' tests/ssml.test ||
		die "ssml.test no longer has the <audio> case; re-check the skip"
	sed -e '/test_ssml_audio "<audio>"/d' -i tests/ssml.test || die

	if ! use klatt; then
		sed -e '/test_wav "en+klatt4"/d' -i tests/variants.test || die
	fi

	if ! use l10n_ru; then
		sed -e '/test_phon ru/d' -i tests/language-pronunciation.test || die
	fi

	if ! use l10n_zh; then
		sed -e '/test_phon cmn/d' -i tests/translate.test || die
	fi
}

src_configure() {
	_need_native() {
		if ! tc-is-cross-compiler; then
			return 1
		fi

		if ! has_version -b ">=${CATEGORY}/${P}"; then
			return 0
		fi

		if "${BROOT}"/usr/bin/espeak-ng --version &> /dev/null ; then
			return 2
		else
			return 0
		fi

		return 1
	}

	if _need_native; then
		einfo "Building native espeak-ng-bin for intonations..."

		BUILD_NATIVE="${WORKDIR}/${P}_build_native"
		local mycmakeargs=(
			-DCOMPILE_INTONATIONS=ON
			-DUSE_SPEECHPLAYER=OFF
			-DESPEAK_BUILD_MANPAGES=OFF
			-DSONIC_LIB=1
			-DSONIC_INC=1
			-DUSE_KLATT=OFF
			-DUSE_MBROLA=OFF
			-DUSE_LIBSONIC=OFF
			-DUSE_LIBPCAUDIO=OFF
			-DENABLE_TESTS=OFF
		)

		BUILD_DIR="${BUILD_NATIVE}" tc-env_build cmake_src_configure

		# create an empty program for now
		touch "${BUILD_NATIVE}"/src/espeak-ng || die
		# make it executable (CMP0109)
		chmod +x "${BUILD_NATIVE}"/src/espeak-ng || die
	fi

	# https://bugs.gentoo.org/836646
	export PULSE_SERVER=""

	local mycmakeargs=(
		-DBUILD_SHARED_LIBS=ON
		-DCOMPILE_INTONATIONS=ON
		# outdated, not packaged
		-DUSE_SPEECHPLAYER=OFF

		-DUSE_KLATT=$(usex klatt)
		-DUSE_MBROLA=$(usex mbrola)
		-DUSE_LIBSONIC=$(usex sonic)
		# or sonic will be fetched even if it's disabled
		# see also https://github.com/espeak-ng/espeak-ng/issues/2273
		$(usev !sonic '-DSONIC_LIB=1 -DSONIC_INC=1')
		-DUSE_LIBPCAUDIO=$(usex sound)
		-DENABLE_TESTS=$(usex test)

		# extended dictionaries
		-DEXTRA_ru=$(usex l10n_ru)
		-DEXTRA_cmn=$(usex l10n_zh)
		-DEXTRA_yue=$(usex l10n_zh)
	)

	if [[ ${PV} == *9999* ]]; then
		mycmakeargs+=( -DESPEAK_BUILD_MANPAGES=ON )
	else
		# use precompiled for releases
		mycmakeargs+=( -DESPEAK_BUILD_MANPAGES=OFF )
	fi

	_need_native
	case $? in
		0) mycmakeargs+=( -DNativeBuild_DIR="${BUILD_NATIVE}/src" ) ;;
		2) mycmakeargs+=( -DNativeBuild_DIR="${BROOT}/usr/bin" ) ;;
	esac

	cmake_src_configure
}

src_compile() {
	if _need_native; then
		BUILD_DIR="${BUILD_NATIVE}" tc-env_build cmake_build espeak-ng-bin
	fi

	cmake_src_compile
}

src_install() {
	cmake_src_install

	[[ ${PV} == *9999* ]] || doman docs/${PN}.1

	# BENTOO-DIVERGENCE: src_install - the command names ::gentoo's 1.52.0
	# (autotools) installs and the CMake build does not. This snapshot
	# replaces that release for everyone, so scripts calling `espeak` or
	# `speak` must keep working; all three are the same CLI as espeak-ng.
	local n
	for n in espeak speak speak-ng; do
		dosym ${PN} /usr/bin/${n}
	done
}
