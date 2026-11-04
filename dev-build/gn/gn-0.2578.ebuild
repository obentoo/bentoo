# Copyright 2018-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
PYTHON_COMPAT=( python3_{11..15} )

# BENTOO-DIVERGENCE: PATCHES - none, where ::gentoo carries
# gn-0.2374-test-iwyu.patch. Verified 2026-09-07: it reverse-applies cleanly
# against the 0.2501 tarball this overlay hosts, so the change is already in.
inherit edo ninja-utils python-any-r1 toolchain-funcs

DESCRIPTION="GN is a meta-build system that generates build files for Ninja"
HOMEPAGE="https://gn.googlesource.com/"
if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="https://gn.googlesource.com/gn"
else
	# The exact commit the published tarball was generated from.  This is the
	# pin, and it is not decoration: `HEAD` moves, so a recipe written in terms
	# of it yields different bytes under the same filename on a different day.
	# ${PV} is itself derived from this commit --
	# `git describe ${GN_COMMIT} --abbrev=12 --match initial-commit` gives
	# initial-commit-2578-g510ec7992c30, hence 0.2578.
	GN_COMMIT="510ec7992c30f172205792f190e96111a896ba8f"

	# Upstream publishes commits, never releases, so somebody has to package a
	# snapshot.  ::gentoo does that on deps.gentoo.zip, which means its mirror
	# only ever carries the version ::gentoo itself is on -- this overlay would
	# be pinned to whatever the distribution shipped.  So the archive is
	# generated and hosted here instead.  The recipe below was proven
	# byte-identical against the 0.2374 tarball deps.gentoo.zip publishes, and
	# again against the 0.2501 tarball this overlay itself publishes:
	#
	#   git clone https://gn.googlesource.com/gn && cd gn
	#   git archive --format=tar --prefix=gn-${PV}/ ${GN_COMMIT} \
	#     | xz -9e > gn-${PV}.tar.xz
	#
	# and uploaded to distfiles.obentoo.org.  A bump is therefore never a plain
	# PV swap: the tarball must be generated and published first, which is why
	# the autoupdate record for this package carries hold = true.
	SRC_URI="https://distfiles.obentoo.org/${P}.tar.xz"
	KEYWORDS="~amd64 ~arm64 ~loong ~ppc64 ~riscv ~x86"
fi

LICENSE="BSD"
SLOT="0"

BDEPEND="
	${PYTHON_DEPS}
	app-alternatives/ninja
"

# gn-0.2374-test-iwyu.patch is gone on purpose: upstream merged it as 07ea23e5,
# the first commit after 0.2374, so re-applying it fails src_prepare.
PATCHES=(
	"${FILESDIR}"/gn-gen-r8.patch
)

pkg_setup() {
	:
}

src_configure() {
	python_setup
	tc-export AR CC CXX
	unset CFLAGS
	set -- ${EPYTHON} build/gen.py --no-last-commit-position --no-strip --no-static-libstdc++ --allow-warnings
	edo "$@"
	# build/gen.py writes this header from `git describe`, which needs a .git
	# dir the tarball does not carry -- hence --no-last-commit-position above
	# and this hand-rolled copy.  Match the string upstream actually emits:
	# build/gen.py formats it as "<num> (<sha12>)", not as the ebuild's PV.
	# This is also what keeps GN_COMMIT load-bearing rather than decorative --
	# a stale pin is visible in `gn --version`, not silent.
	local commit_id=${GN_COMMIT:-UNKNOWN}
	cat >out/last_commit_position.h <<-EOF || die
	#ifndef OUT_LAST_COMMIT_POSITION_H_
	#define OUT_LAST_COMMIT_POSITION_H_
	#define LAST_COMMIT_POSITION_NUM ${PV##0.}
	#define LAST_COMMIT_POSITION "${PV##0.} (${commit_id:0:12})"
	#endif  // OUT_LAST_COMMIT_POSITION_H_
	EOF
}

src_compile() {
	eninja -C out gn
}

src_test() {
	eninja -C out gn_unittests
	out/gn_unittests || die
}

src_install() {
	dobin out/gn
	einstalldocs

	insinto /usr/share/vim/vimfiles
	doins -r misc/vim/{autoload,ftdetect,ftplugin,syntax}
}
