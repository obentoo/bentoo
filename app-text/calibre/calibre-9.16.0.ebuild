# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# calibre 9.x sets requires-python = ">=3.14" in pyproject.toml and setup.py
# aborts on anything older, so this cannot be widened. python3_15 is left out
# on purpose: dev-lang/python:3.15 is still at _rc in ::gentoo and upstream
# does not test against it.
# BENTOO-DIVERGENCE: IUSE_DEFAULTS - python_single_target_python3_14 is the
# only possible default: calibre 9.x sets requires-python = ">=3.14", so the
# compat list below cannot be widened and the single target follows it.
PYTHON_COMPAT=( python3_14 )
PYTHON_REQ_USE="sqlite,ssl"

inherit edo toolchain-funcs python-single-r1 qmake-utils verify-sig xdg

DESCRIPTION="Ebook management application"
HOMEPAGE="https://calibre-ebook.com/"
SRC_URI="
	https://download.calibre-ebook.com/${PV}/${P}.tar.xz
	verify-sig? ( https://calibre-ebook.com/signatures/${P}.tar.xz.sig )
"
VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/kovidgoyal.gpg

LICENSE="
	GPL-3+
	GPL-3
	GPL-2+
	GPL-2
	GPL-1+
	LGPL-3+
	LGPL-2.1+
	LGPL-2.1
	BSD
	MIT
	Old-MIT
	Apache-2.0
	public-domain
	|| ( Artistic GPL-1+ )
	CC-BY-3.0
	OFL-1.1
	PSF-2
"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
# BENTOO-DIVERGENCE: IUSE - no python_single_target_python3_12 or _13, which
# ::gentoo's 8.15 still exposes. Same cause as the REQUIRED_USE tag below: the
# calibre 9 series needs Python 3.14, so those two targets cannot build it and
# there is no flag to offer.
IUSE="+font-subsetting ios speech +system-mathjax test +udisks unrar"

RESTRICT="!test? ( test )"

# BENTOO-DIVERGENCE: REQUIRED_USE - python3_14 alone, where ::gentoo still
# accepts 3.12 and 3.13. Not a narrowing taken for its own sake: the calibre 9
# series requires Python 3.14, so the older targets cannot build it at all.
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

# BENTOO-DIVERGENCE: DEPEND - app-text/podofo:1 instead of :0, because calibre
# 9.15.0 ported its bindings to the PoDoFo 1.x API (PdfErrorCode::FlateError,
# AppendDocumentPages(), PdfMemDocument::CreateDestination(), one-argument
# CreateChild()), none of which 0.10.x can provide; upstream pins podofo 1.1.2
# in bypy/sources.json. app-text/podofo:1 is overlay-only and installs into a
# private prefix, so :0 stays available for app-office/scribus and
# kde-misc/krename.
#
# Qt slotted dependencies are used because the libheadless.so plugin links to
# QT_*_PRIVATE_ABI. It only uses core/gui/dbus.
COMMON_DEPEND="${PYTHON_DEPS}
	app-i18n/uchardet
	>=app-text/hunspell-1.7:=
	>=app-text/podofo-1.1.0:1=[jpeg,png]
	app-text/poppler[utils]
	dev-libs/hyphen:=
	>=dev-libs/icu-57.1:=
	dev-libs/openssl:=
	dev-libs/snowball-stemmer:=
	$(python_gen_cond_dep '
		>=dev-python/apsw-3.25.2_p1[${PYTHON_USEDEP}]
		dev-python/beautifulsoup4[${PYTHON_USEDEP}]
		>=dev-python/css-parser-1.0.4[${PYTHON_USEDEP}]
		dev-python/dnspython[${PYTHON_USEDEP}]
		>=dev-python/feedparser-6.0.14[${PYTHON_USEDEP}]
		>=dev-python/html2text-2019.8.11[${PYTHON_USEDEP}]
		>=dev-python/html5-parser-0.4.9[${PYTHON_USEDEP}]
		dev-python/jeepney[${PYTHON_USEDEP}]
		>=dev-python/lxml-3.8.0[${PYTHON_USEDEP}]
		dev-python/lxml-html-clean[${PYTHON_USEDEP}]
		>=dev-python/markdown-3.0.1[${PYTHON_USEDEP}]
		>=dev-python/mechanize-0.3.5[${PYTHON_USEDEP}]
		>=dev-python/msgpack-0.6.2[${PYTHON_USEDEP}]
		>=dev-python/netifaces-0.10.5[${PYTHON_USEDEP}]
		>=dev-python/pillow-3.2.0[jpeg,truetype,webp,zlib,${PYTHON_USEDEP}]
		>=dev-python/psutil-4.3.0[${PYTHON_USEDEP}]
		>=dev-python/pychm-0.8.6[${PYTHON_USEDEP}]
		dev-python/pykakasi[${PYTHON_USEDEP}]
		>=dev-python/pygments-2.3.1[${PYTHON_USEDEP}]
		>=dev-python/python-dateutil-2.5.3[${PYTHON_USEDEP}]
		dev-python/pyqt6[gui,network,opengl,printsupport,quick,svg,widgets,${PYTHON_USEDEP}]
		dev-python/pyqt6-webengine[widgets,${PYTHON_USEDEP}]
		dev-python/pystache[${PYTHON_USEDEP}]
		dev-python/regex[${PYTHON_USEDEP}]
		dev-python/tzlocal[${PYTHON_USEDEP}]
		dev-python/xxhash[${PYTHON_USEDEP}]
		>=dev-python/zeroconf-0.75.0[${PYTHON_USEDEP}]
	')
	dev-qt/qtbase:6=[gui,widgets]
	dev-qt/qtimageformats:6
	dev-util/desktop-file-utils
	dev-util/gtk-update-icon-cache
	media-fonts/liberation-fonts
	media-libs/fontconfig:=
	>=media-libs/freetype-2:=
	>=media-libs/libmtp-1.1.11:=
	>=media-gfx/optipng-0.7.6
	>=media-video/ffmpeg-6:=
	virtual/libusb:1=
	x11-misc/shared-mime-info
	>=x11-misc/xdg-utils-1.0.2-r2
	font-subsetting? ( $(python_gen_cond_dep 'dev-python/fonttools[${PYTHON_USEDEP}]') )
	ios? (
		>=app-pda/usbmuxd-1.0.8
		>=app-pda/libimobiledevice-1.2.0
	)
	speech? (
		$(python_gen_cond_dep 'app-accessibility/speech-dispatcher[python,${PYTHON_USEDEP}]')
		dev-python/pyqt6[multimedia,speech]
	)
	system-mathjax? ( >=dev-libs/mathjax-3:= )
	udisks? ( virtual/libudev )
	unrar? ( dev-python/unrardll )
"
# BENTOO-DIVERGENCE: RDEPEND - same two, through COMMON_DEPEND above.
RDEPEND="${COMMON_DEPEND}
	udisks? ( sys-fs/udisks:2 )"
# BENTOO-DIVERGENCE: DEPEND - pystache and tzlocal, new imports in the 9.x
# series; ::gentoo is on 8.x and needs neither.
DEPEND="${COMMON_DEPEND}
	test? ( $(python_gen_cond_dep '>=dev-python/chardet-3.0.3[${PYTHON_USEDEP}]') )
"
# dev-build/cmake is needed because setup.py build_headless() shells out to
# cmake + make to build the libheadless.so Qt platform plugin. ::gentoo leaves
# this dependency implicit.
#
# The rapydscript-ng floor is load-bearing and new in the 9.x series: upstream
# raised its external-compiler check from >=0.7.5 to >=0.8.5 (see
# external_compiler_version() in src/calibre/utils/rapydscript.py). Below the
# floor the check does not error -- it silently reports "no external compiler"
# and falls back to the compiler embedded in Qt WebEngine, which then tries to
# mkdir inside /usr and dies on a sandbox violation halfway through
# src_compile. ::gentoo's dependency is unversioned and its rapydscript-ng is
# 0.7.22, so USE=system-mathjax cannot build there at all; this overlay carries
# 0.8.6 for it. An unversioned atom here would turn a dependency error into
# that sandbox failure, so do not drop the >=.
# BENTOO-DIVERGENCE: BDEPEND - dev-build/cmake, made explicit here. setup.py
# build_headless() shells out to cmake to build libheadless.so; ::gentoo
# leaves it implicit, which works only when cmake happens to be present.
# app-misc/pax-utils is for the scanelf guard in src_compile that proves the
# podofo extension linked the right slot.
BDEPEND="$(python_gen_cond_dep '
		>=dev-python/pyqt-builder-1.10.3[${PYTHON_USEDEP}]
		>=dev-python/sip-5[${PYTHON_USEDEP}]
	')
	virtual/pkgconfig
	app-misc/pax-utils
	dev-build/cmake
	system-mathjax? ( >=dev-lang/rapydscript-ng-0.8.5 )
	verify-sig? ( sec-keys/openpgp-keys-kovidgoyal )
"

# BENTOO-DIVERGENCE: PATCHES - same two fixes as ::gentoo (jxr-test, piper),
# rebased onto 9.x; the names carry the series they were rebased for.
PATCHES=(
	# Skip calling a binary (JxrDecApp) from libjxr which is used for tests
	# We don't (yet?) package libjxr and it seems to be dead upstream
	# (last commit in 2017)
	"${FILESDIR}/${PN}-9.13.0-jxr-test.patch"
	"${FILESDIR}/${PN}-9.13.0-piper.patch"
)

src_prepare() {
	default

	# Warning:
	#
	# While it might be rather tempting to add yet another sed here,
	# please don't. There have been several bugs in Gentoo's packaging
	# of calibre from seds-which-become-stale. Please consider
	# creating a patch instead, but in any case, run the test suite
	# and ensure it passes.
	#
	# If in doubt about a problem, checking Fedora's packaging is recommended.

	# Disable privilege dropping for bug #287067 and generally because desktop
	# login user != portage.
	sed -e "s:SUDO_:__DISABLED_SUDO_:" \
		-i setup/__init__.py || die

	# This is only ever used at build time. It contains a small embedded copy
	# of the rapydscript-ng compiler usable inside of qtwebengine, if you don't
	# have rapydscript-ng (a nodejs package) itself installed. Its only purpose
	# is to build some resources that come bundled in dist tarballs already...
	# and which we may also need to regenerate e.g. to use system-mathjax.
	#
	# However, running qtwebengine violates the portage sandbox (among other
	# things, it tries to create directories in /usr! amazing) so this is a
	# wash anyway. The only real solution here is to package rapydscript-ng.
	#
	# We do not need it at build time, and *no one* needs it at install time.
	# Delete the cruft.
	rm -r resources/rapydscript/ || die
}

src_compile() {
	# TODO: get qmake called by setup.py to respect CC and CXX too
	tc-export CC CXX

	# bug 821871
	local MY_LIBDIR="${ESYSROOT}/usr/$(get_libdir)"
	export FT_LIB_DIR="${MY_LIBDIR}" HUNSPELL_LIB_DIR="${MY_LIBDIR}"

	# app-text/podofo:1 is installed into a private prefix so that it can
	# coexist with slot 0 (see the dependency comment above). Nothing there is
	# in a default search path, so point setup.py at it explicitly and record
	# an RPATH: setup/build.py appends ${LDFLAGS} to the link line verbatim.
	#
	# PODOFO_INC_DIR must be the directory *containing* podofo.h, because
	# build.py also adds its parent, which is what makes <podofo/podofo.h>
	# resolve.
	#
	# PODOFO_LIB_NAME is the one that must be an absolute path, and it is not
	# belt and braces. build.py emits "-L/usr/lib64 -lpython3.14 ... -L<the
	# private prefix> -lpodofo", and ld scans every -L in command-line order
	# for each -l: plain "-lpodofo" therefore finds slot 0's
	# /usr/lib64/libpodofo.so FIRST. That does not fail the build -- a -shared
	# link leaves undefined symbols alone -- it just yields an extension
	# compiled against the 1.x headers and linked to libpodofo.so.2, which
	# dies at import time. build.py passes any library name containing a "/"
	# through verbatim (setup/build.py, libraries_to_ldflags), so an absolute
	# path removes the search entirely. The check after the build proves it.
	local podofo_libdir="${ESYSROOT}/usr/$(get_libdir)/podofo-1"
	export PODOFO_INC_DIR="${ESYSROOT}/usr/include/podofo-1/podofo"
	export PODOFO_LIB_DIR="${podofo_libdir}"
	export PODOFO_LIB_NAME="${podofo_libdir}/libpodofo.so"
	export LDFLAGS="${LDFLAGS} -Wl,-rpath,${EPREFIX}/usr/$(get_libdir)/podofo-1"
	export QMAKE="$(qt6_get_bindir)/qmake"

	edo ${EPYTHON} setup.py build

	# Guard for the -L ordering described above: assert the extension needs
	# the SONAME of the slot it was compiled against, whatever that number is
	# (4 for podofo-1.1.x, 2 for the 0.10.x line in ::gentoo).
	local want got
	want=$(scanelf -qF '%S#F' "${podofo_libdir}/libpodofo.so") || die
	got=$(scanelf -qF '%n#F' src/calibre/plugins/podofo.so) || die
	[[ ,${got}, == *,${want},* ]] ||
		die "podofo.so needs '${got}', expected '${want}': the wrong PoDoFo slot was linked in"
	edo ${EPYTHON} setup.py gui

	# A few different resources are bundled in the distfile by default, because
	# not all systems necessarily have them. We un-vendor them, using the
	# upstream integrated approach if possible. See setup/revendor.py and
	# consider migrating other resources to this if they do not use it, in
	# *preference* over manual rm'ing.
	edo ${EPYTHON} setup.py liberation_fonts \
		--path-to-liberation_fonts "${EPREFIX}"/usr/share/fonts/liberation-fonts \
		--system-liberation_fonts
	if use system-mathjax; then
		edo ${EPYTHON} setup.py mathjax --path-to-mathjax "${EPREFIX}"/usr/share/mathjax --system-mathjax
		edo ${EPYTHON} setup.py rapydscript
	fi
}

src_test() {
	# Skipped tests:
	local _test_excludes=(
		# unpackaged Python dependency: py7zr
		7z
		# unpackaged Python dependency: pyzstd
		test_zstd
		# unpackaged TTS backend (optional at runtime): https://github.com/rhasspy/piper
		piper
		# tests if a completely unused module is bundled
		pycryptodome

		$(usev !speech speech_dispatcher)
		$(usev !unrar test_unrar)

		# undocumented reasons
		test_mem_leaks
		test_searching
	)

	# Some of these tests weren't practical to split out into distinct tests, so
	# have a different control mechanism
	use speech || export SKIP_SPEECH_TESTS=1

	edo ${PYTHON} setup.py test "${_test_excludes[@]/#/--exclude-test-name=}"
}

src_install() {
	# Bug #352625 - Some LANGUAGE values can trigger the following ValueError:
	#   File "/usr/lib/python2.6/locale.py", line 486, in getdefaultlocale
	#    return _parse_localename(localename)
	#  File "/usr/lib/python2.6/locale.py", line 418, in _parse_localename
	#    raise ValueError, 'unknown locale: %s' % localename
	#ValueError: unknown locale: 46
	export -n LANG LANGUAGE ${!LC_*}
	export LC_ALL=C.UTF-8 # bug #709682

	# Bug #295672 - Avoid sandbox violation in ~/.config by forcing
	# variables to point to our fake temporary $HOME.
	export HOME="${T}/fake_homedir"
	export CALIBRE_CONFIG_DIRECTORY="${HOME}/.config/calibre"
	mkdir -p "${CALIBRE_CONFIG_DIRECTORY}" || die

	addpredict /dev/dri #665310

	# If this directory doesn't exist, zsh completion won't install
	dodir /usr/share/zsh/site-functions

	edo "${PYTHON}" setup.py install \
		--staging-root="${ED}/usr" \
		--prefix="${EPREFIX}/usr" \
		--libdir="${EPREFIX}/usr/$(get_libdir)" \
		--staging-libdir="${ED}/usr/$(get_libdir)" \
		--system-plugins-location="${EPREFIX}/usr/share/calibre/system-plugins"

	cp -r man-pages/ "${ED}"/usr/share/man || die

	find "${ED}"/usr/share -type d -empty -delete || die

	python_fix_shebang "${ED}/usr/bin"

	python_optimize "${ED}"/usr/$(get_libdir)/calibre "${D}/$(python_get_sitedir)"

	newinitd "${FILESDIR}"/calibre-server-3.init calibre-server
	newconfd "${FILESDIR}"/calibre-server-3.conf calibre-server
}
