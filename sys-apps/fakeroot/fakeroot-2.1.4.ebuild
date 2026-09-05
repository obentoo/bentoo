# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# OVERLAY NOTE -- WHY THIS IS HERE AND WHAT CHANGED SINCE ::gentoo's 1.33.
#
# ::gentoo still carries 1.33 (2025).  Debian, which is where fakeroot is
# actually developed, has shipped the 2.x series since July 2026; 2.1.4 is the
# current unstable/testing version.  Drop this ebuild once ::gentoo catches up.
#
# Differences from the ::gentoo 1.33 ebuild:
#
# 1) The release tarball is .orig.tar.xz now, not .orig.tar.gz.
#
# 2) Both ::gentoo patches were dropped:
#    - fakeroot-1.32.2-configure-id_t.patch is merged upstream (configure.ac
#      has AC_CHECK_TYPE(id_t, int) since 1.35.1), and
#    - fakeroot-1.32.2-musl.patch no longer applies.  Its libfakeroot.c half
#      (the SEND_GET_XATTR macro) is upstream too; only the faked.c format
#      strings still matter, so that half was rebased -- see the patch header.
#
# 3) Upstream now ships a meson build alongside autotools and says in
#    INSTALL.md that one of the two will eventually go away.  Autotools is
#    kept here because it is what ::gentoo uses and what the po4a man page
#    translations are wired into.  Re-evaluate if upstream drops it.
#
# The tarball ships no configure script (upstream deliberately stopped
# shipping autotools-generated files), so eautoreconf is mandatory, not a
# convenience.

PLOCALES="de es fr nl pt ro sv"
inherit autotools flag-o-matic plocale

DESCRIPTION="A fake root environment by means of LD_PRELOAD and SysV IPC (or TCP) trickery"
HOMEPAGE="https://tracker.debian.org/pkg/fakeroot"
SRC_URI="mirror://debian/pool/main/${PN:0:1}/${PN}/${P/-/_}.orig.tar.xz"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~alpha ~amd64 ~arm ~arm64 ~hppa ~ppc ~ppc64 ~riscv ~s390 ~sparc ~x86"
IUSE="acl debug nls test"
RESTRICT="!test? ( test )"

DEPEND="
	sys-libs/libcap
	acl? ( sys-apps/acl )
	test? ( app-arch/sharutils )
"
BDEPEND="nls? ( app-text/po4a )"

DOCS=( AUTHORS BUGS DEBUG INSTALL.md README doc/README.saving )

# BENTOO-DIVERGENCE: PATCHES - the musl fix rebased from ::gentoo's 1.32.2
# onto 2.1.4; the content differs, not just the name. Its configure-id_t
# companion is gone because 2.1.4 fixed that upstream.
PATCHES=(
	"${FILESDIR}/${PN}-2.1.4-musl.patch"
)

src_prepare() {
	default

	disable_locale() {
		local locale=${1}

		sed -i -e "s: ${locale}::" doc/po4a/po4a.cfg doc/Makefile.am || die
	}

	plocale_find_changes doc/po4a/po '' '.po'
	plocale_for_each_disabled_locale disable_locale

	# t.xattr2 fails wherever the build runs unprivileged -- it checks that a
	# setfattr done under fakeroot did NOT reach the real filesystem, and that
	# check does not hold on every filesystem.  It fails on Debian's own
	# buildds too, which is why Debian carries the very same skip as a patch
	# (debian/patches/0001-Disable-t.xattr2-*.patch).  Exit 77 is automake's
	# "skipped", not "passed".
	sed -i -e '/^\. \.\/defs || exit 1$/a exit 77' test/t.xattr2 || die

	# We could make this conditional and disable the autodependency in
	# autotools.eclass but it'd make it too easy for NLS builds to be broken
	# and us not realise.
	eautoreconf
}

src_configure() {
	export ac_cv_header_sys_acl_h=$(usex acl)
	use acl || export ac_cv_search_acl_get_fd=no # bug 759568
	use debug && append-cppflags -DLIBFAKEROOT_DEBUGGING

	# https://bugs.gentoo.org/834445
	# https://gcc.gnu.org/bugzilla/show_bug.cgi?id=101270
	filter-flags -fno-semantic-interposition

	econf --disable-static
}

src_compile() {
	local enabled_locales=$(plocale_get_locales)

	if use nls && [[ -n ${enabled_locales} ]] ; then
		# Create translated man pages
		pushd doc >/dev/null || die
		po4a -v -k 0 --variable "srcdir=${S}/doc/" po4a/po4a.cfg || die
		popd >/dev/null || die
	fi

	default
}

src_install() {
	default

	# no static archives
	find "${ED}" -name '*.la' -delete || die
}
