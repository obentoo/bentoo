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
SLOT="26"
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

IUSE="cpu_flags_x86_sse2 debug doc +icu +inspector lto +npm pax-kernel pnpm +snapshot +ssl +system-icu +system-ssl test"
REQUIRED_USE="inspector? ( icu ssl )
	npm? ( ssl )
	system-icu? ( icu )
	system-ssl? ( ssl )
	x86? ( cpu_flags_x86_sse2 )"

RESTRICT="!test? ( test )"

COMMON_DEPEND=">=app-arch/brotli-1.2.0:=
	dev-db/sqlite:3
	>=dev-cpp/ada-3.4.4:=
	>=dev-libs/libuv-1.52.1:=
	>=dev-libs/simdjson-4.6.1:=
	>=net-dns/c-ares-1.34.6:=
	>=net-libs/nghttp2-1.69.0:=
	>=net-libs/nghttp3-1.18.0:=
	virtual/zlib:=
	system-icu? ( >=dev-libs/icu-73:= )
	system-ssl? (
		>=net-libs/ngtcp2-1.22.1:=
		>=dev-libs/openssl-3.5.6:0=
	)
	!system-ssl? ( >=net-libs/ngtcp2-1.22.1:=[-gnutls] )
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

	# fix compilation on Darwin
	# https://code.google.com/p/gyp/issues/detail?id=260
	#
	# The pattern matters: the file spells it append("-arch") on one line with
	# the architecture on the next, so the old single-quoted /append('-arch/d
	# matched nothing at all and deleted neither line -- verified against this
	# tarball. An anchored sed that matches nothing still exits 0, so `|| die`
	# never saw it. ::gentoo corrected this in its own 26.3.0.
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

	# Build fixes carried from ::gentoo's 26.7.0 (it lists these as a global
	# PATCHES array; this ebuild has none, so they go here). gcc17 is a
	# bentoo-local rebase -- see the header of the 26.7.0 copy for why the
	# ::gentoo 26.6.0 one cannot be used verbatim.
	PATCHES+=(
		"${FILESDIR}"/${PN}-26.7.0-gcc17.patch
		"${FILESDIR}"/${PN}-26.6.0-format-cstdlib.patch
		"${FILESDIR}"/${PN}-26.6.0-v8-climits.patch
	)

	# We need to disable mprotect on two files when it builds Bug 694100.
	#
	# A 26.5.1-specific copy, NOT the shared ${PN}-24.1.0-paxmarking.patch:
	# against this tarball that file applies with "fuzz 1" in both node.gyp
	# (its context still names src/node_webstorage.h, which 26 replaced with
	# src/ffi/types.h) and tools/v8_gypfiles/v8.gyp. Fuzz cannot be sat on --
	# portage's __eapply_patch greps its own output for "with fuzz", prints it
	# and still returns SUCCESS, so a hunk that drifts to the wrong site ships
	# silently and only breaks at compile time, only for USE=pax-kernel users.
	# The rebased copy applies with --fuzz=0 and produces a byte-identical
	# result to the original.
	use pax-kernel &&
		PATCHES+=( "${FILESDIR}"/${PN}-26.5.1-paxmarking.patch )

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
