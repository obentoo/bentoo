# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit bash-completion-r1 readme.gentoo-r1

DESCRIPTION="Google's UI toolkit for building natively compiled apps"
HOMEPAGE="https://flutter.dev/"
SRC_URI="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${PV}-stable.tar.xz"

# The tarball extracts into a top-level flutter/ directory.
S="${WORKDIR}/${PN}"

LICENSE="BSD"
SLOT="0"
KEYWORDS="-* ~amd64"
IUSE="examples"
RESTRICT="bindist mirror strip"

QA_PREBUILT="*"

# This release bundles Dart SDK 3.14.0 (see dart_sdk_version in upstream's
# releases_linux.json). src_install replaces the bundled SDK with the system
# one, so the version must match exactly: bin/cache/flutter_tools.snapshot only
# loads on the Dart VM it was compiled against. Keep this pin in sync with the
# dart_sdk_version of ${PV}, and keep the matching dev-lang/dart ebuild in the
# tree even after dart is bumped.
#
# The pin is what the revision is for: .autoupdate bumps PV without reading
# RDEPEND, so every bump arrives carrying the PREVIOUS release's pin and merges
# against a Dart the snapshot was not built on. A plain edit would not reinstall
# it -- only a revbump does. Four bumps in a row have now arrived this way:
# 3.47.2 needed -r1 (5810abcc9), 3.47.3 landed in 941ba854d still pinning
# 3.13.2 after upstream moved the stable channel to 3.13.3 on 2026-09-09,
# 3.47.5 landed pinning 3.13.3 after the channel moved to 3.13.4 on 2026-09-15,
# and 3.47.6 landed in 98aa62c2e pinning 3.13.4 after 3.13.5 shipped on
# 2026-09-29.
# Nothing in the tree catches it -- "emerge -pv" stays green and only the
# flutter binary fails, at runtime. Treat a flutter bump as unfinished until
# this line is re-derived from the source, never from the changelog:
#
#   curl -s 'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json' \
#     | jq -r '.releases[] | select(.channel=="stable") | "\(.version)\t\(.dart_sdk_version)"' | head
#
# acct-group/flutter is a DEPEND as well as an RDEPEND: src_install calls
# fowners, and the fowners helper resolves the group name against
# ${ESYSROOT}/etc/group, so the group has to exist at build time.
DEPEND="acct-group/flutter"
RDEPEND="
	${DEPEND}
	~dev-lang/dart-3.14.0
"

DOC_CONTENTS="The Flutter SDK is installed in /opt/flutter.

Unlike an ordinary program, the flutter tool writes into its own SDK tree on
every single invocation: it stamps bin/cache/, takes a lock there, downloads
platform artifacts on demand, populates packages/flutter_tools/.dart_tool/,
and runs 'git fetch' in the bundled repository. A read-only tree is therefore
not merely limited, it does not work at all.

That tree is owned by the 'flutter' group and is group-writable. To use
flutter, add yourself to that group and start a new login session:

    gpasswd -a <user> flutter

Note the consequence: every member of the 'flutter' group can modify the SDK
that the other members execute. Add only users you would trust with that.

Do NOT copy /opt/flutter into your home directory as a way around the group.
bin/cache/dart-sdk is an absolute symlink to /usr/lib/dart, so a copy stays
bound to whatever dev-lang/dart is installed system-wide. The next dart bump
leaves the copy's flutter_tools.snapshot compiled against the previous Dart
VM, and every command then fails with:

    Wrong full snapshot version, expected '<new>' found '<old>'

Only the tree installed by this package is kept in step with dev-lang/dart,
because the ebuild pins the exact Dart version the SDK was built against."

src_prepare() {
	default
	# Drop Windows batch launchers; they are useless on Gentoo.
	find . -iname '*.bat' -delete || die
}

src_compile() {
	# The flutter tool needs a dart-sdk to generate completions. The bundled
	# bin/cache/dart-sdk is still present here (it is only unbundled during
	# src_install), so this works.
	einfo "Building completions"
	"bin/${PN}" bash-completion "${PN}.bash-completion" > /dev/null || die
}

src_install() {
	use examples || { rm -r examples/ || die; }

	# Unbundle the Dart SDK: remove the vendored copy and point the cache at
	# the system dev-lang/dart tree (installed at /usr/lib/dart by this overlay).
	rm -r bin/cache/dart-sdk || die

	newbashcomp "${PN}.bash-completion" "${PN}"
	rm "${PN}.bash-completion" || die

	# dodoc writes into ${ED}, so this belongs in src_install; calling it from
	# src_compile produced no /usr/share/doc entry at all.
	DISABLE_AUTOFORMATTING=1 readme.gentoo_create_doc

	dodir /opt
	mv "${S}" "${ED}/opt/${PN}" || die

	# The flutter tool rewrites its own SDK tree on every run (see
	# DOC_CONTENTS), so the tree has to be writable by its users. Hand it to
	# the 'flutter' group rather than to a single account or to everyone.
	# Ordering matters: this runs before the dart-sdk symlink is created, so
	# neither chown nor chmod can reach /usr/lib/dart through it.
	fowners -R root:flutter "/opt/${PN}"
	fperms -R g+w "/opt/${PN}"
	# setgid on directories, so files created by one group member stay
	# group-owned by 'flutter' and remain writable for the others.
	find "${ED}/opt/${PN}" -type d -exec chmod g+s {} + || die

	# Absolute symlink into the system Dart SDK installed by dev-lang/dart.
	dosym /usr/lib/dart "/opt/${PN}/bin/cache/dart-sdk"
	dosym "../${PN}/bin/${PN}" "/opt/bin/${PN}"
}

pkg_postinst() {
	readme.gentoo_print_elog
}
