# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

CONFIG_CHECK="~ADVISE_SYSCALLS"
PYTHON_COMPAT=( python3_{11..14} )
PYTHON_REQ_USE="threads(+)"

# bash-completion-r1 is deliberately absent: its only consumer here was
# newbashcomp, and the npm completion now goes inside the slot prefix (see
# src_install) instead of into the shared /usr/share/bash-completion/completions
# that eclass installs to. Nothing else in this ebuild uses shell-completion.
inherit check-reqs flag-o-matic linux-info
inherit ninja-utils pax-utils python-any-r1 toolchain-funcs xdg-utils

DESCRIPTION="A JavaScript runtime built on Chrome's V8 JavaScript engine"
HOMEPAGE="https://nodejs.org/"
LICENSE="Apache-1.1 Apache-2.0 BlueOak-1.0.0 BSD BSD-2 MIT npm? ( Artistic-2 )"

# The slot is this ebuild's major version. It is spelt as an unindented literal
# at column 0, not as $(ver_cut 1), because the overlay's autoupdate engine
# scrapes it with a plain text regex anchored at ^SLOT= -- it neither sources the
# ebuild nor reads metadata/md5-cache, so an indented or computed value is
# invisible to it and the per-slot record cannot resolve a current version.
# scripts/check-slot-naming-contract.sh asserts this literal matches the major in
# the filename, which is what a computed value used to guarantee: copy this file
# to a new major and forget to change the line, and that check fails.
SLOT="24"
if [[ ${PV} == *9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/nodejs/node"
	# The live ebuild stays unslotted, as ::gentoo has it. Assigned after the
	# literal above so it wins for 9999 while the scraper still sees the real
	# slot on the release branch.
	SLOT="0"
else
	SRC_URI="https://nodejs.org/dist/v${PV}/node-v${PV}.tar.xz"
	KEYWORDS="~amd64 ~arm ~arm64 ~loong ~ppc64 ~riscv ~x86 ~x64-macos"
	S="${WORKDIR}/node-v${PV}"
fi

# BENTOO-DIVERGENCE: IUSE - "pnpm", absent from ::gentoo. PDEPEND-only; it
# pulls sys-apps/pnpm, which ships as its own package here.
#
# BENTOO-DIVERGENCE: IUSE_DEFAULTS - "+system-icu" where ::gentoo leaves it off.
# Default-on unbundles ICU for everyone: a bundled ICU is a second copy of the
# timezone and locale data that no dev-libs/icu update reaches.
IUSE="cpu_flags_x86_sse2 debug doc +icu +inspector lto +npm pax-kernel pnpm +snapshot +ssl +system-icu +system-ssl test"
REQUIRED_USE="inspector? ( icu ssl )
	npm? ( ssl )
	system-icu? ( icu )
	system-ssl? ( ssl )
	x86? ( cpu_flags_x86_sse2 )"

RESTRICT="!test? ( test )"

# Version-driven bounds, taken from ::gentoo's own 24 series
# (nodejs-24.16.0-r1) rather than from the 26 ebuild: a 26-era floor would
# reject libraries slot 24 builds against perfectly well. This block, SRC_URI
# and PATCHES are the only places the two slots are expected to differ.
#
# What these numbers are NOT is a mirror of what deps/ vendors. They are the
# floors ::gentoo's 24 maintainer settled on -- the oldest API each --shared-*
# link is known to work against. Measured against this tarball, deps/ is ahead
# of several of them, and that is fine:
#
#   dep       floor here  24.18.1 has  26.5.1 has  ::gentoo has
#   ada       3.3.0       3.4.4        3.4.4       3.4.4
#   brotli    1.1.0       1.2.0        1.2.0       1.2.0-r1
#   c-ares    1.34.5      1.34.6       1.34.6      1.34.8
#   libuv     1.52.1      1.52.1       1.52.1      1.52.1
#   simdjson  4.6.1       4.6.4        4.6.4       4.6.2
#   nghttp2   1.69.0      1.69.0       1.69.0      1.69.0
#   nghttp3   1.14.0      1.14.0       1.17.0      1.18.0
#   ngtcp2    1.14.0      1.15.1       1.23.0      1.25.0
#   openssl   3.5.6       3.5.7        3.5.7       3.6.3
#
# Left alone deliberately, and the simdjson row is why: "raise every floor to
# whatever deps/ vendors" is the obvious-looking rule and it is wrong. deps/
# vendors simdjson 4.6.4 while ::gentoo ships at most 4.6.2, so that rule
# makes the package uninstallable. A floor is a claim about an API, and
# raising one without a build behind it buys a user-visible restriction with
# no evidence. Move a line here when a build actually fails below it.
#
# Two rows are real 24-vs-26 differences rather than staleness -- nghttp3 and
# ngtcp2. 24.18.1 vendors 1.14.0 and 1.15.1 where 26.5.1 vendors 1.17.0 and
# 1.23.0, so the 26 ebuild's higher floors would simply be wrong here. ada and
# brotli, by contrast, have CONVERGED since ::gentoo's 24.16.0-r1 snapshot:
# both majors now vendor 3.4.4 and 1.2.0. Their floors differ only because
# ::gentoo's 24 ebuild predates that, not because the series disagree.
#
# dev-cpp/simdutf is DELIBERATELY ABSENT, matching this overlay's 26 ebuild
# and diverging from ::gentoo, which carries >=dev-cpp/simdutf-7.3.4:= plus
# --shared-simdutf on BOTH its 24.16.0-r1 and its 26.3.0. That is the whole
# point: it is a bentoo decision about the package, not a difference between
# majors, so re-adding it here alone would split the two slots on a choice
# that is not allowed to differ between them.
#
# It also stands on its own merits. --shared-simdutf does not REPLACE the
# bundled copy, it adds a second one. Node 24.18.1 ships no top-level
# deps/simdutf; the only copy is deps/v8/third_party/simdutf, v6.4.0.
# node_shared_simdutf gates exactly two places -- node.gypi:237 (node's own
# target) and node.gyp:1525 (the host js2c tool) -- while
# tools/v8_gypfiles/v8.gyp:1079 makes v8_base_without_compiler depend on that
# vendored simdutf UNCONDITIONALLY. So with the flag on, node's src/*.cc
# compiles against the system headers (dev-cpp/simdutf is 9.0.0 here) while
# V8 compiles against 6.4.0, and both land in one binary. Neither side uses a
# versioned namespace -- both spell it plain `simdutf::`, 435 such symbols in
# libsimdutf.so.34 -- so that is an ODR violation, not a tidy substitution.
#
# Weighed against Gentoo's prefer-system-libraries policy, which genuinely
# points the other way. If that wins, the change belongs on BOTH slots and
# needs a real build on each: --shared-simdutf has never been exercised in
# this overlay, whereas the fallback has (slot 26, commit ecb7586e).
COMMON_DEPEND=">=app-arch/brotli-1.1.0:=
	dev-db/sqlite:3
	>=dev-cpp/ada-3.3.0:=
	>=dev-libs/libuv-1.52.1:=
	>=dev-libs/simdjson-4.6.1:=
	>=net-dns/c-ares-1.34.5:=
	>=net-libs/nghttp2-1.69.0:=
	>=net-libs/nghttp3-1.14.0:=
	virtual/zlib:=
	system-icu? ( >=dev-libs/icu-73:= )
	system-ssl? (
		>=net-libs/ngtcp2-1.14.0:=
		>=dev-libs/openssl-3.5.6:0=
	)
	!system-ssl? ( >=net-libs/ngtcp2-1.14.0:=[-gnutls] )
	|| (
		sys-devel/gcc:*
		llvm-runtimes/libatomic-stub
	)"
BDEPEND="${PYTHON_DEPS}
	app-alternatives/ninja
	sys-apps/coreutils
	virtual/pkgconfig
	test? ( net-misc/curl )
	pax-kernel? ( sys-apps/elfix )"
DEPEND="${COMMON_DEPEND}"
# app-eselect/eselect-nodejs is a *runtime* dependency, not a build one: no
# src_* phase touches it, but pkg_postinst and pkg_postrm run `eselect nodejs`.
# It owns every unversioned path -- /usr/bin/{node,npm,npx}, /usr/include/node,
# the shared bash-completion file, /usr/share/man/man1/node.1 -- plus /etc/npm
# and /etc/env.d/50npm, which this ebuild used to install itself. Without it a
# merged slot is reachable only as node26, never as plain `node`.
#
# The blocker is STRONG (!!) and it is the whole of R4.1/R4.4. net-libs/nodejs:0
# is the pre-slotting package: it installs those same unversioned paths
# directly, so it and app-eselect/eselect-nodejs cannot coexist even for a
# moment -- with FEATURES="protect-owned" the merge aborts on the first shared
# path. A weak (!) blocker permits exactly that momentary coexistence, which is
# why it is not enough here; !! makes portage unmerge the old package first and
# surfaces the conflict during dependency resolution, before any file is
# written.
#
# ":0" is a slot dependency, not a version range, so it needs no maintenance as
# majors go by: it matches the unslotted package (SLOT="0", recorded as "0/26"
# with its sub-slot) and matches no slotted one (SLOT="26"). Caveat for whoever
# adds a live ebuild: the ${PV} == *9999 branch above still sets SLOT="0", and a
# !! blocker is *not* ignored against a package in the parent's own slot
# (depgraph.py checks `not blocker.atom.blocker.overlap.forbid`, false for !!),
# so that branch would need its own SLOT before this atom is correct for it.
# >=eselect-nodejs-2 is a correctness bound, not hygiene: module version 1 made
# /usr/bin/node a symlink, and `readlink -f` on a symlink reports the slot's real
# path rather than /usr/bin/node itself. Consumers that link to /usr/bin/node and
# then verify with `readlink -f` compare two different strings and die -
# www-client/chromium does exactly that in src_prepare. Version 2 writes an exec
# wrapper, which resolves to itself. Pinning the floor here keeps a downgrade of
# the module from silently reintroducing that failure in every such consumer.
RDEPEND="${COMMON_DEPEND}
	>=app-eselect/eselect-nodejs-2
	!!net-libs/nodejs:0"
PDEPEND="pnpm? ( sys-apps/pnpm )"

# These are measured on a loong machine with -ggdb on, and only checked
# if debugging flags are present in CFLAGS.
#
# The final link consumed a little more than 7GiB alone, so 8GiB is the lower
# limit for memory usage. Disk usage was 19.1GiB for the build directory and
# 1.2GiB for the installed image, so we leave some room for architectures with
# fatter binaries and set the disk requirement to 22GiB.
CHECKREQS_MEMORY="8G"
CHECKREQS_DISK_BUILD="22G"

# BENTOO-DIVERGENCE: PATCHES - a different set from ::gentoo's 26.8.1, which
# is the baseline the parity sweep picks for this ebuild. Both halves are
# reasoned out below: what is here, and what is deliberately absent.
# (The reasoning predates this tag; the tag exists so gentoo-parity.sh can
# see it.)
#
# The 26 ebuild has no global PATCHES at all; this one does, and that is
# expected -- a patch exists because a particular major's source needs it, so
# PATCHES is one of the three places (with SRC_URI and the dependency bounds
# above) where two slots of the same recipe legitimately differ.
#
# The 32-bit patch is V8 upstream commit ddfa1b3d ("[turboshaft] Rename TupleOp
# to MakeTupleOp to avoid name conflicts"), backported for
# https://bugs.gentoo.org/969806, where the unrenamed TupleOp collides on
# 32-bit targets -- ~arm and ~x86 here. Carried verbatim from ::gentoo, byte for
# byte, so a future sync can diff it. Verified still NEEDED at 24.18.1, not
# merely still applying: a dry run takes all 50 hunks forward (with offsets),
# whereas a patch already merged upstream comes back reversed.
#
# DELIBERATELY ABSENT -- do not reintroduce ::gentoo 24.16.0-r1's second entry:
#   SRC_URI += https://deps.gentoo.zip/net-libs/nodejs/${P}-nghttp2-1.69.0.patch
#   PATCHES += "${DISTDIR}"/${P}-nghttp2-1.69.0.patch
# It backported upstream's own adaptation to the nghttp2 1.69.0 API into a
# 24.16.0 that still vendored 1.67.x. At 24.18.1 upstream has done that itself:
# deps/nghttp2/lib/includes/nghttp2/nghttp2ver.h reads NGHTTP2_VERSION "1.69.0",
# so the tree already speaks the API that >=net-libs/nghttp2-1.69.0:= provides.
# The patch is also version-stamped and simply does not exist for this release
# -- deps.gentoo.zip serves it for 24.16.0 only (24.17.0, 24.18.0 and 24.18.1
# all return 404), so carrying the entry forward would break fetching outright.
PATCHES=(
	"${FILESDIR}"/${PN}-24.14.0-32-bit.patch
)

pkg_pretend() {
	if [[ ${MERGE_TYPE} != "binary" ]]; then
		if is-flagq "-g*" && ! is-flagq "-g*0" ; then
			einfo "Checking for sufficient disk space and memory to build ${PN} with debugging CFLAGS"
			check-reqs_pkg_pretend
		fi
	fi
}

pkg_setup() {
	python-any-r1_pkg_setup
	linux-info_pkg_setup

	# tools/install.py derives *every* destination from the prefix configure.py
	# was given -- bin/node, include/node/, lib/node_modules/npm/ and
	# share/man/man1/node.1 -- so one prefix per slot is the whole isolation
	# mechanism. dev-lang/php (PHP_DESTDIR) is the in-tree precedent.
	#
	# Relative to EPREFIX: configure.py gets "${EPREFIX}${NODE_SLOT_DIR}",
	# src_install writes into "${ED}${NODE_SLOT_DIR}". Keep it in sync with
	# app-eselect/eselect-nodejs, which finds slots by globbing
	# ${EROOT}/usr/lib*/node-[0-9]* for an executable bin/node.
	#
	# Assigned here, not in global scope: the package manager replaces
	# get_libdir() with a die stub during the depend phase, so a global
	# assignment breaks metadata generation. pkg_setup runs ahead of every
	# other phase and portage carries the value in the saved phase environment.
	NODE_SLOT_DIR="/usr/$(get_libdir)/node-${SLOT}"
}

src_prepare() {
	tc-export AR CC CXX PKG_CONFIG
	export V=1
	export BUILDTYPE=Release

	# fix compilation on Darwin (~x64-macos)
	# https://code.google.com/p/gyp/issues/detail?id=260
	#
	# The expression, NOT the one the 26 ebuild and ::gentoo's 24 series both
	# still carry. gyp-next 0.22.2 -- the copy vendored here -- writes the pair
	# as two separately quoted lines:
	#     cflags.append("-arch")
	#     cflags.append(archs[0])
	# so the old `/append('-arch/d` matches NOTHING in this tree (grepped: the
	# single-quoted spelling occurs nowhere under ${S}), and an anchored sed
	# that matches nothing still exits 0 -- `|| die` cannot see it. {N;d;} takes
	# both lines of each pair, at 665/666 and 947/948. ::gentoo made the same
	# correction in its 26.3.0 ebuild.
	sed -i -e '/append("-arch")/{N;d;}' tools/gyp/pylib/gyp/xcode_emulation.py || die

	# DELIBERATELY ABSENT -- do not reintroduce the ::gentoo libdir seds:
	#   sed -i -e "s|lib/|$(get_libdir)/|g" tools/install.py
	#   sed -i -e "s/'lib'/'$(get_libdir)'/" deps/npm/lib/npm.js
	# (hat tip @ryanpcmcquen https://github.com/iojs/io.js/issues/504)
	#
	# They exist only because ::gentoo installs into the shared /usr, where
	# "lib" would be wrong on a lib64 profile. This ebuild gives every slot its
	# own prefix (${NODE_SLOT_DIR}), so <prefix>/lib is already unambiguous --
	# nothing else lives there to collide with.
	#
	# Upstream keeps both sides of the global npm root in agreement already:
	#   tools/install.py:91      os.path.join('lib/node_modules', name)
	#   deps/npm/lib/npm.js:492  resolve(globalPrefix, 'lib', 'node_modules')
	# so the two paths match with no rewriting. Rewriting one and not the other
	# makes `npm root -g` point at an empty directory with no error, which is
	# why these must be deleted or kept as a pair, never merged back piecemeal.
	# src_install's LIBDIR follows this choice and must move with it.
	#
	# The install.py sed was over-broad besides: s|lib/|lib64/|g also rewrote
	# 'deps/zlib/zconf.h' and 'include/node/zoslib/' (harmless only because we
	# build --shared-zlib on non-z/OS).

	# Avoid writing a depfile, not useful
	sed -i -e "/DEPFLAGS =/d" tools/gyp/pylib/gyp/generator/make.py || die

	sed -i -e "/'-O3'/d" common.gypi node.gypi || die

	# debug builds. change install path, remove optimisations and override buildtype
	if use debug; then
		sed -i -e "s|out/Release/|out/Debug/|g" tools/install.py || die
		BUILDTYPE=Debug
	fi

	# We need to disable mprotect on two files when it builds Bug 694100.
	#
	# A 24.18.1-specific copy, NOT the ${PN}-24.1.0-paxmarking.patch that
	# ::gentoo and this overlay's 26 ebuild both point at. Same change byte
	# for byte -- only the @@ line numbers and the context lines around them
	# were regenerated -- but the 24.1.0 file lands its last hunk here "with
	# fuzz 1", because 24.18.1 inserted a node_with_ltcg conditional into the
	# mksnapshot target's 'conditions' list, splitting the three lines that
	# hunk anchors on.
	#
	# Fuzz is treated as a failure rather than a warning, and the reason is
	# that nothing downstream will treat it as one: portage's __eapply_patch
	# greps its own output for "with fuzz", prints the line, and still
	# returns SUCCESS. A fuzzy hunk that drifted one target further down
	# would still produce a syntactically valid gyp file, so the first
	# symptom would be a compile error -- and only under USE=pax-kernel,
	# which is off by default, so it could sit unnoticed for majors.
	#
	# Checked, not assumed: at 24.18.1 the fuzzy application does land on the
	# correct site, and this rebased file reproduces its output byte for byte
	# (identical sha256 on both patched files). It is replaced anyway so the
	# next bump cannot inherit the drift silently -- the point is to make the
	# anchor exact again, not to fix a bug that has already bitten.
	#
	# Slot 26 is NOT fixed by this and is deliberately left alone: repointing
	# it is a cross-slot change. For the record, 26.5.1 fuzzes on the shared
	# file twice -- v8.gyp hunk 3 for the same reason as here, plus node.gyp
	# hunk 1, where upstream swapped 'src/node_webstorage.h' for
	# 'src/ffi/types.h' in the context.
	use pax-kernel &&
		PATCHES+=( "${FILESDIR}"/${PN}-24.18.1-paxmarking.patch )

	use ppc64 &&
		PATCHES+=(	"${FILESDIR}/${PN}-24.11.1-restore-ppc64be.patch" )

	default
}

src_configure() {
	xdg_environment_reset

	# LTO compiler flags are handled by configure.py itself
	filter-lto
	# The warnings are *so* noisy and make build.logs massive
	append-cxxflags $(test-flags-CXX -Wno-template-id-cdtor)
	# https://bugs.gentoo.org/931514
	use arm64 && append-flags $(test-flags-CXX -mbranch-protection=none)

	local myconf=(
		--ninja
		--shared-ada
		--shared-brotli
		--shared-cares
		--shared-libuv
		--shared-nghttp2
		--shared-nghttp3
		--shared-ngtcp2
		--shared-simdjson
		--shared-sqlite
		--shared-zlib
	)
	use debug && myconf+=( --debug )
	use lto && myconf+=( --enable-lto )
	if use system-icu; then
		myconf+=( --with-intl=system-icu )
	elif use icu; then
		myconf+=( --with-intl=full-icu )
	else
		myconf+=( --with-intl=none )
	fi
	# Corepack off, and on this major that takes an EXPLICIT flag.
	#
	# ::gentoo's 24 series exposes USE=corepack; this overlay does not, on
	# either slot -- corepack would put a fourth binary (plus the yarn/pnpm
	# shims it enables) into the same /usr/bin that app-eselect/eselect-nodejs
	# arbitrates, and it carries `corepack? ( !sys-apps/yarn )`, a blocker whose
	# whole purpose is that collision. Dropping the flag is what keeps both
	# slots exposing one surface and eselect managing exactly three names.
	#
	# The flag polarity FLIPPED between the two majors, so "off" is not the same
	# code in both files. Read from each release's own configure.py:
	#   24.18.1  parser.add_argument('--without-corepack', ..., default=None)
	#            node_install_corepack = b(not options.without_corepack)
	#            -> default None, so `not None` is True: OMITTING THE FLAG
	#               INSTALLS COREPACK. Opt-out.
	#   26.5.1   node_install_corepack = b(options.with_corepack)
	#            -> default off; omission is already "off". Opt-in.
	# Hence this line exists here and has no counterpart in the 26 ebuild, and
	# it is unconditional rather than `use corepack ||` because there is no such
	# USE flag to read. tools/install.py:209 gates corepack_files() on that one
	# variable, so this is the only thing standing between the slot prefix and
	# a bin/corepack nobody asked for.
	myconf+=( --without-corepack )
	use inspector || myconf+=( --without-inspector )
	use npm || myconf+=( --without-npm )
	use snapshot || myconf+=( --without-node-snapshot )
	if use ssl; then
		use system-ssl && myconf+=( --shared-openssl --openssl-use-def-ca-store )
	else
		myconf+=( --without-ssl )
	fi

	local myarch=""
	case "${ARCH}:${ABI}" in
		*:amd64) myarch="x64";;
		*:arm) myarch="arm";;
		*:arm64) myarch="arm64";;
		loong:lp64*) myarch="loong64";;
		riscv:lp64*) myarch="riscv64";;
		*:ppc64) myarch="ppc64";;
		*:x32) myarch="x32";;
		*:x86) myarch="ia32";;
		*) myarch="${ABI}";;
	esac

	GYP_DEFINES="linux_use_gold_flags=0
		linux_use_bundled_binutils=0
		linux_use_bundled_gold=0" \
	"${EPYTHON}" configure.py \
		--prefix="${EPREFIX}${NODE_SLOT_DIR}" \
		--dest-cpu=${myarch} \
		"${myconf[@]}" || die
}

src_compile() {
	eninja -C out/Release
}

src_install() {
	# npm's tree lands inside the slot prefix at <prefix>/lib -- the literal
	# string "lib", NOT $(get_libdir). That is what tools/install.py:91 writes
	# and what deps/npm/lib/npm.js:492 resolves at runtime, now that
	# src_prepare no longer rewrites either (see the note there before
	# "correcting" this to $(get_libdir) -- the two must move together).
	local LIBDIR="${ED}${NODE_SLOT_DIR}/lib"
	default

	pax-mark -m "${ED}${NODE_SLOT_DIR}"/bin/node

	# No include/node symlink farm here. The old "structure that node-gyp
	# expects" (src -> . ; deps/{uv,v8}/include -> ../..) is CYCLIC: it makes
	# include/node/src/src/src/... and include/node/deps/v8/include/deps/v8/
	# include/... expand forever. ::gentoo dropped it for that reason, and any
	# consumer that walks /usr/include recursively without cycle detection
	# spins until it is OOM-killed -- chromium >=150 does exactly that, via
	# gn's expand_directory() (bentoo#35, Gentoo bug #980202 WONTFIX: the fix
	# belongs here, not in chromium/gn). The headers themselves are installed
	# by the plain `default`/emake install above; nothing else is needed.

	# Version-suffixed entry points (R1.4). These are the only /usr/bin paths
	# this ebuild owns: the unsuffixed node/npm/npx belong to
	# app-eselect/eselect-nodejs, which repoints them on every switch. Both
	# layers exist so a user can pin one major (node26) while `node` keeps
	# following whatever was selected.
	#
	# dosym -r (EAPI 8) derives the *relative* target from the two absolute
	# paths -- /usr/bin/node26 -> ../lib64/node-26/bin/node -- instead of a
	# hand-spelt "../$(get_libdir)/node-${SLOT}/bin/node". Same link value,
	# but it stays derived from ${NODE_SLOT_DIR}, the one place the prefix is
	# defined, so the two cannot drift; and it is exactly what link_target()
	# in the eselect module computes for the unversioned links. Relative is
	# not cosmetic: with ROOT set (an offline install) an absolute target
	# names a path on the *build host* and points nowhere once that tree is
	# booted into.
	#
	# npm and npx are conditional because install.py creates bin/npm and
	# bin/npx only when npm is installed -- an unconditional dosym would leave
	# two dangling links in /usr/bin under USE=-npm. create_symlinks() in the
	# eselect module skips the same two paths for the same reason.
	local versioned_entries=( node )
	if use npm; then
		versioned_entries+=( npm npx )
	fi
	local entry
	for entry in "${versioned_entries[@]}"; do
		dosym -r "${NODE_SLOT_DIR}/bin/${entry}" "/usr/bin/${entry}${SLOT}"
	done

	if use doc; then
		docinto html
		dodoc -r "${S}"/doc/*
	fi

	if use npm; then
		# Pin npm and npx to *this* slot's interpreter. Upstream ships
		# "#!/usr/bin/env node", which resolves through PATH -- so npm26 would
		# execute slot 26's npm code under whichever slot eselect happens to
		# have activated. That is not cosmetic: npm derives its global root
		# from dirname(dirname(process.execPath)), so under a foreign
		# interpreter `npm root -g` reports the *other* slot's tree while
		# loading this slot's code. install.py symlinks bin/{npm,npx} to these
		# two files, so they are the only entry points that need it (the third
		# "#!/usr/bin/env node" under npm/bin/, npm-prefix.js, is reachable
		# only from the cygwin/mingw bin/npm wrapper, which already passes an
		# explicit interpreter; bin/node-gyp is created on z/OS only).
		#
		# Anchored with 1s and ^...$ so it cannot match any other line. It is
		# verified afterwards because an anchored sed that matches NOTHING
		# still exits 0 -- `|| die` cannot see the silent no-op that an
		# upstream shebang change would cause, and the resulting cross-slot
		# mix would only surface at runtime.
		local npm_bindir="${ED}${NODE_SLOT_DIR}/lib/node_modules/npm/bin"
		local slot_shebang="#!${EPREFIX}${NODE_SLOT_DIR}/bin/node"
		local npm_cli
		for npm_cli in npm npx; do
			sed -i -e "1s|^#!/usr/bin/env node\$|${slot_shebang}|" \
				"${npm_bindir}/${npm_cli}-cli.js" ||
				die "sed failed on ${npm_cli}-cli.js"
			[[ $(head -n 1 "${npm_bindir}/${npm_cli}-cli.js") == "${slot_shebang}" ]] ||
				die "${npm_cli}-cli.js line 1 is not ${slot_shebang} -- upstream shebang changed?"
		done

		# DELIBERATELY ABSENT -- do not reintroduce:
		#   keepdir /etc/npm
		#   echo "NPM_CONFIG_GLOBALCONFIG=..." > "${T}"/50npm; doenvd "${T}"/50npm
		# Neither path is slot-specific, so two installed slots would own the
		# same two files and FEATURES="protect-owned" would turn that into a
		# merge failure. app-eselect/eselect-nodejs, which is single-instance
		# by construction, owns them now -- that is what keeps
		# NPM_CONFIG_GLOBALCONFIG naming one shared npmrc for every slot
		# (R7.2) while the runtime itself is slotted.

		# Bash completion for `npm`, installed inside the slot prefix rather
		# than into the shared /usr/share/bash-completion/completions that
		# newbashcomp targets -- same collision argument as /etc/npm above and
		# as npm's manpages below. app-eselect/eselect-nodejs links the shared
		# path at the active slot's copy on every switch.
		#
		# The destination is a CONTRACT with that module, not a preference. Its
		# NODEJS_LINKS carries the pair
		#   /usr/share/bash-completion/completions/npm
		#     |share/bash-completion/completions/npm
		# whose right-hand side is relative to the slot prefix, and
		# create_symlinks() *skips* an entry whose source is missing -- that
		# branch exists so a USE=-npm slot leaves no dangling link behind. So a
		# file installed one directory off raises no error anywhere: `npm <TAB>`
		# simply stays dead. Move one spelling and you must move the other.
		local tmp_npm_completion_file="$(TMPDIR="${T}" mktemp -t npm.XXXXXXXXXX)"
		# Name the interpreter instead of letting bin/npm's shebang pick it:
		# that shebang now points at ${EPREFIX}${NODE_SLOT_DIR}/bin/node, which
		# does not exist yet -- the binary is still staged under ${ED} -- so
		# going through it would fail with "bad interpreter". Being explicit
		# also decouples this build-time call from shebang state entirely, so
		# reordering src_install cannot silently reintroduce that breakage.
		# It runs the freshly built node on the build host, as the build
		# already does for the V8 snapshot.
		#
		# The `|| die` is load-bearing and not decoration: the redirect creates
		# the file before node ever runs, so a failing invocation still leaves a
		# 0-byte completion behind -- and a 0-byte completion installs, sources
		# and reports nothing. The only symptom would be a tab key that does
		# nothing, months later.
		"${ED}${NODE_SLOT_DIR}"/bin/node "${npm_bindir}"/npm-cli.js completion \
			> "${tmp_npm_completion_file}" || die "generating npm completion failed"

		# The body of newbashcomp, verbatim apart from the destination:
		# subshell so insinto/insopts cannot leak into a later phase, and an
		# explicit 0644 so a stray insopts earlier in src_install cannot make
		# the completion executable or unreadable.
		(
			insopts -m 0644
			insinto "${NODE_SLOT_DIR}"/share/bash-completion/completions
			newins "${tmp_npm_completion_file}" npm
		)

		# npm's manpages go inside the slot prefix, NOT into the shared
		# /usr/share/man that `doman` targets. Two installed slots would each
		# write share/man/man1/npm-install.1 to that one path -- a collision,
		# and with FEATURES="protect-owned" a merge failure. Inside the prefix
		# they are slot-owned, and app-eselect/eselect-nodejs's single MANPATH
		# entry in /etc/env.d/50nodejs names the *active* slot's share/man,
		# covering man1, man5 and man7 at once (R7.3). Accepted consequence:
		# `man npm-install` resolves for the active slot only -- there is no
		# way to spell `man npm-install26`. dev-lang/php does the same, with
		# /usr/lib64/php8.5/man on MANPATH.
		#
		# Moved rather than copied, then linked back: npm reads these pages
		# from its own tree too -- help.js:63 globs
		# resolve(npmRoot, "man/<sec>/?(npm-)<arg>.[0-9]*") -- so `npm help
		# install` needs <prefix>/lib/node_modules/npm/man to keep resolving.
		# ::gentoo's doman kept that working by accident, because doman copies.
		# One directory symlink keeps both readers on a single copy that
		# cannot drift, instead of 709K of duplicated pages.
		local npm_mandir="${ED}${NODE_SLOT_DIR}/lib/node_modules/npm/man"
		local mansec
		for mansec in 1 5 7; do
			# Loud on an upstream reorganisation: quietly shipping fewer
			# sections would regress R7.3 with nothing to notice it.
			[[ -d ${npm_mandir}/man${mansec} ]] ||
				die "npm ships no man${mansec} -- upstream man layout changed?"
			# man1 already exists -- install.py:204 put node.1 there -- while
			# man5 and man7 do not. No npm page is named node.1, so the merge
			# clobbers nothing; asserted after the loop rather than assumed.
			dodir "${NODE_SLOT_DIR}/share/man/man${mansec}"
			mv "${npm_mandir}/man${mansec}"/* \
				"${ED}${NODE_SLOT_DIR}/share/man/man${mansec}"/ ||
				die "moving npm man${mansec} pages failed"
			rmdir "${npm_mandir}/man${mansec}" ||
				die "npm man${mansec} still has entries after the move"
		done
		[[ -f "${ED}${NODE_SLOT_DIR}/share/man/man1/node.1" ]] ||
			die "node.1 is gone -- an npm page collided with it"

		# dosym refuses to write over a real directory (and plain `ln -sfn`
		# would silently nest the link inside it), so emptying it first is
		# what makes the symlink legal, not just tidy.
		rmdir "${npm_mandir}" || die "unexpected leftovers in ${npm_mandir}"
		dosym -r "${NODE_SLOT_DIR}/share/man" \
			"${NODE_SLOT_DIR}/lib/node_modules/npm/man"

		# Clean up
		rm -f "${LIBDIR}"/node_modules/npm/{.mailmap,.npmignore,Makefile}

		local find_exp="-or -name"
		local find_name=()
		for match in "AUTHORS*" "CHANGELOG*" "CONTRIBUT*" "README*" \
			".travis.yml" ".eslint*" ".wercker.yml" ".npmignore" \
			"*.bat" "*.cmd"; do
			find_name+=( ${find_exp} "${match}" )
		done

		# Remove various development and/or inappropriate files and
		# useless docs of dependend packages.  Source files are spared by
		# extension, because these patterns match module *names*, not only
		# docs: `-iname "LICEN?E*"` also eats the runtime modules
		# @npmcli/package-json/lib/license.js (new in 7.0.5, bundled here)
		# and @npmcli/arborist/bin/license.js, and without the former any
		# `npm init` path dies with MODULE_NOT_FOUND.  Nothing else in the
		# bundled npm tree matches both a pattern and a code extension, so
		# the exclusion costs the cleanup nothing.
		find "${LIBDIR}"/node_modules \
			\( -type d -name examples \) -or \( -type f \
				! -name "*.cjs" ! -name "*.js" ! -name "*.json" \
				! -name "*.mjs" ! -name "*.ts" \( \
				-iname "LICEN?E*" \
				"${find_name[@]}" \
			\) \) -exec rm -rf "{}" \;
	fi

	# install.py drops gdbinit/lldb_commands.py into <prefix>/share/doc/node;
	# /usr/share/doc/${PF} is already unique per slot, so they stay there.
	mv "${ED}${NODE_SLOT_DIR}"/share/doc/node "${ED}"/usr/share/doc/${PF} || die
}

src_test() {
	local drop_tests=(
		test/parallel/test-dns.js
		test/parallel/test-dns-resolveany-bad-ancount.js
		test/parallel/test-dns-setserver-when-querying.js
		test/parallel/test-dotenv.js
		test/parallel/test-fs-mkdir.js
		test/parallel/test-fs-read-stream.js
		test/parallel/test-fs-utimes-y2K38.js
		test/parallel/test-fs-watch-recursive-add-file.js
		test/parallel/test-http2-client-set-priority.js
		test/parallel/test-http2-priority-event.js
		test/parallel/test-process-euid-egid.js
		test/parallel/test-process-get-builtin.mjs
		test/parallel/test-process-initgroups.js
		test/parallel/test-process-setgroups.js
		test/parallel/test-process-uid-gid.js
		test/parallel/test-release-npm.js
		test/parallel/test-socket-write-after-fin-error.js
		test/parallel/test-strace-openat-openssl.js
		test/sequential/test-tls-session-timeout.js
		test/sequential/test-util-debug.js
		# Breaking change in nghttp2 1.67.1, see
		# https://github.com/nodejs/node/issues/60661
		# https://github.com/nodejs/node/commit/b426a47c05e6b039ed65798d0ad3b3698b35fd97
		# https://github.com/nghttp2/nghttp2/issues/2604
		test/parallel/test-http2-client-unescaped-path.js
		test/parallel/test-http2-multi-content-length.js
		test/parallel/test-http2-reset-flood.js
		test/parallel/test-http2-max-invalid-frames.js
		test/parallel/test-http2-misbehaving-flow-control.js
		test/parallel/test-http2-misbehaving-flow-control-paused.js
	)
	# https://bugs.gentoo.org/963649
	has_version '>=dev-libs/openssl-3.6' &&
		drop_tests+=(
			test/parallel/test-tls-ocsp-callback
		)
	use inspector ||
		drop_tests+=(
			test/parallel/test-inspector-emit-protocol-event.js
			test/parallel/test-inspector-network-arbitrary-data.js
			test/parallel/test-inspector-network-domain.js
			test/parallel/test-inspector-network-fetch.js
			test/parallel/test-inspector-network-http.js
			test/sequential/test-watch-mode.mjs
		)
	rm -f "${drop_tests[@]}" || die "disabling tests failed"

	out/${BUILDTYPE}/cctest || die
	"${EPYTHON}" tools/test.py --mode=${BUILDTYPE,,} --flaky-tests=dontcare -J message parallel sequential || die
}

# The default-slot policy (R3.5, R3.6), in two rules:
#
#   nothing active  -> activate this slot. A merged runtime with no
#                      /usr/bin/node is broken for every consumer.
#   something active -> never change it. Speak up only when the selection can
#                      actually break a build.
#
# Why not simply "always activate the newest": all 72 references to this
# package across ::gentoo and this overlay are UNSLOTTED atoms
# (net-libs/nodejs, >=net-libs/nodejs-N), so every one of them resolves through
# /usr/bin/node, the link app-eselect/eselect-nodejs owns. Switching silently
# would break someone who pinned an older major on purpose; saying nothing
# would let www-client/chromium's >=net-libs/nodejs-${NODE_VER} fail with
# nothing pointing at the active slot as the cause. The elog is the
# compromise: the user is told and decides.
#
# No --root=: eselect derives its EROOT from the ROOT and EPREFIX that portage
# already exports into pkg_* phases (/usr/bin/eselect, "EROOT=${ROOT%...}..."
# near the top), so these calls are ROOT-scoped without the flag. Passing
# --root= would additionally set ROOT as a variable *inside* eselect that is
# never exported, which the `env update` do_set ends with would not see --
# app-editors/emacs passes it, but its module has no such tail call.
pkg_postinst() {
	local active
	active=$(eselect nodejs show)

	if [[ -z ${active} ]]; then
		# `show` prints zero bytes -- and exits 0 -- for all three unusable
		# states: no /usr/bin/node, a /usr/bin/node that is not a symlink (the
		# leftover of the unslotted net-libs/nodejs:0), and a link into a slot
		# that has been unmerged. That is why the branch is on the *output*
		# and never on the exit status; see describe_show in the module.
		#
		# Status-checked and warned rather than `die`d: a `die -q` inside an
		# eselect module exits 250, and an unchecked call as the last command
		# of this phase would hand that to portage as the phase's result. By
		# postinst the files are already merged, so failing here would report
		# a broken install for what is one `eselect nodejs set` away from
		# fixed.
		if eselect nodejs set "node${SLOT}"; then
			elog "No Node.js slot was active, so ${PN}:${SLOT} is now the default."
			elog "Change it at any time with: eselect nodejs set <slot>"
		else
			ewarn "Could not activate Node.js slot ${SLOT}."
			ewarn "/usr/bin/node is still unset, so anything invoking plain"
			ewarn "\`node\` will fail. This slot does run as \`node${SLOT}\`."
			ewarn "Once the cause is fixed, activate it with:"
			ewarn "    eselect nodejs set node${SLOT}"
		fi
	else
		# ${active} is a slot NAME (node24) while ${SLOT} is a bare major (26),
		# so the two majors are compared NUMERICALLY. A string compare would
		# put node9 above node26 and fire this message backwards -- the same
		# trap find_targets() avoids with `sort -V`. 10# forces base 10, so a
		# hypothetical node08 is 8 rather than an octal syntax error, and the
		# ^[0-9]+$ guard means a name that is not node<digits> falls through to
		# doing nothing, which is the safe direction: never hijack.
		local active_major=${active#node}
		if [[ ${active_major} =~ ^[0-9]+$ ]] &&
			(( 10#${active_major} < 10#${SLOT} )); then
			elog "Node.js slot ${SLOT} is newer than the active slot (${active}), which"
			elog "was left alone: overriding a deliberate choice is not this"
			elog "ebuild's call."
			elog
			elog "It is worth saying because no consumer depends on a *slot* of"
			elog "net-libs/nodejs -- they all use plain atoms and so resolve"
			elog "through /usr/bin/node, which still runs ${active}. One that needs"
			elog "${SLOT} (www-client/chromium carries >=net-libs/nodejs-<major>)"
			elog "would fail with nothing naming the active slot as the cause."
			elog "To switch:"
			elog "    eselect nodejs set node${SLOT}"
			elog "Either way this slot is always reachable as \`node${SLOT}\`."
		fi
		# Deliberately silent in the other two directions:
		#
		#   active == this slot  nothing changed. A line here would print on
		#                        every routine upgrade of the active slot.
		#   active >  this slot  no hazard exists. An active node<newer>
		#                        already satisfies every bound this slot could,
		#                        so no unslotted consumer can break; installing
		#                        an older major alongside a newer one is a
		#                        deliberate act, and it runs as `node${SLOT}`.
		#
		# Both would recur on every upgrade of a slot the user is content with,
		# and a message people learn to skip is worse than no message: it would
		# dilute the one above, which reports a real problem. dev-lang/php's
		# pkg_postinst elogs in both directions; this is the deliberate
		# difference.
	fi

	if use npm; then
		ewarn "remember to run: source /etc/profile if you plan to use nodejs"
		ewarn " in your current shell"
	fi
}

# R3.4's repair path. `cleanup` is not merely "remove what dangles": once it
# finds any dead managed link it drops the whole managed set, then re-points it
# at the highest slot still installed -- or, when this was the last slot, takes
# the links and /etc/env.d/50nodejs away.
#
# Correct on a re-emerge too, which is worth spelling out because this phase
# runs then as well -- portage unmerges the OLD instance from inside the new
# one's merge. Verified in portage 3.0's dbapi/vartree.py: _merge_contents()
# (line ~5126) puts the new files on disk BEFORE the old instance is unmerged
# (~5201), and that unmerge is handed `others_in_slot`, so _unmerge_pkgfiles()
# skips every path the new instance owns (isowner(), ~2902). Nothing under
# /usr/lib*/node-${SLOT} disappears, nothing dangles, and cleanup returns
# without touching the selection -- one "No dangling Node.js links found."
# line.
#
# So the call is unconditional rather than gated on ${REPLACED_BY_VERSION},
# which would skip the one same-slot case that does need it: a rebuild that
# drops USE=npm leaves /usr/bin/npm pointing at a file the new instance does
# not install, and this is what repairs it.
#
# Its output is deliberately NOT suppressed -- eselect's --brief would hide
# exactly the "No dangling Node.js links found." line while keeping the
# ones that report a change. An unmerge that silently rearranges /usr/bin/node
# is the failure mode this design exists to avoid, so the healthy case saying
# so out loud is what tells "checked, fine" apart from "never ran".
#
# Status-checked and warned, never `die`d, for pkg_postinst's reason plus one
# more: app-eselect/eselect-nodejs is an RDEPEND, so a depclean is free to
# unmerge it before this package. `eselect nodejs cleanup` then exits non-zero
# because the module is gone, and as the last command of this phase that would
# fail the unmerge of an already-unmerged package. dev-lang/php's pkg_postrm
# carries the same caveat as a comment, without the check.
# BENTOO-DIVERGENCE: DEFINED_PHASES - pkg_postrm, which ::gentoo does not need.
# This overlay slots nodejs by major version where ::gentoo ships one unslotted
# package, so removing a slot leaves /usr/bin/node pointing into a directory
# that is gone; `eselect nodejs cleanup` repoints it.
#
# BENTOO-DIVERGENCE: RDEPEND - app-eselect/eselect-nodejs and the
# "!!net-libs/nodejs" blocker, both from that same slotting: the eselect module
# owns the symlinks, the blocker stops an unslotted copy overwriting them.
pkg_postrm() {
	if ! eselect nodejs cleanup; then
		ewarn "\`eselect nodejs cleanup\` failed."
		ewarn "/usr/bin/node and its siblings may still point into the slot"
		ewarn "that was just removed, which makes them fail at exec time"
		ewarn "rather than at lookup time. Once app-eselect/eselect-nodejs is"
		ewarn "installed, repair them with:"
		ewarn "    eselect nodejs cleanup"
	fi
}
