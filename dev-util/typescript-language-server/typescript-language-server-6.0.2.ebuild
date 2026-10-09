# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Language Server Protocol implementation for TypeScript using tsserver"
HOMEPAGE="https://github.com/typescript-language-server/typescript-language-server"
# Upstream distributes through npm only. lib/cli.mjs is a rollup bundle that
# already inlines every runtime module, so no node_modules tree is needed.
# tsserver is not bundled either: the server prefers the typescript of the
# project being edited and a tsserver.path from the client, and otherwise
# falls back to require.resolve('typescript'). That fallback is what makes it
# work on plain JavaScript projects, so a private copy of the last JavaScript
# TypeScript series is installed next to the server. It is private, not
# dev-lang/typescript, because TypeScript 7 (the native Go port, in the same
# slot) ships neither tsserver.js nor lib/typescript.js: depending on the
# system package would force <dev-lang/typescript-7 on everyone who wants
# this server.
TS_PV="6.0.3"
SRC_URI="
	https://registry.npmjs.org/${PN}/-/${P}.tgz
	https://registry.npmjs.org/typescript/-/typescript-${TS_PV}.tgz
"
S="${WORKDIR}/${PN}"

# Apache-2.0: the server; MIT: code taken from vscode and the bundled
# commander, fs-extra, vscode-languageserver* and friends; ISC: semver, which,
# graceful-fs; BlueOak-1.0.0: isexe. The private typescript is Apache-2.0.
LICENSE="Apache-2.0 BlueOak-1.0.0 ISC MIT"
SLOT="0"
# Pure JavaScript: nothing here is architecture-specific.
KEYWORDS="~amd64 ~arm64"

RDEPEND=">=net-libs/nodejs-22.22.2:*"

src_unpack() {
	# Both npm tarballs unpack to "package"; give each its own directory.
	local a
	for a in ${PN}:${P}.tgz typescript:typescript-${TS_PV}.tgz; do
		mkdir "${WORKDIR}"/${a%%:*} || die
		tar -xzf "${DISTDIR}"/${a#*:} -C "${WORKDIR}"/${a%%:*} \
			--strip-components=1 || die
	done
}

src_install() {
	insinto /usr/share/${PN}
	doins -r lib package.json

	# require.resolve walks up from lib/cli.mjs, so a node_modules entry next
	# to it is what the server reports as the "bundled" typescript. Only the
	# runtime part is installed: lib/ (tsserver.js, typescript.js, the lib.*.d.ts
	# declarations) and package.json. bin/ is left out: the server loads
	# tsserver.js directly, and a tsc on PATH belongs to dev-lang/typescript.
	#
	# It goes in lib/node_modules, the first directory that walk tries, and
	# not in ${PN}/node_modules: up to -r1 that path was a symlink to
	# /usr/lib/node_modules/typescript. Portage merges a directory through a
	# symlink already on disk instead of replacing it, so on an upgrade the
	# files landed in dev-lang/typescript's tree and the merge died on file
	# collisions.
	insinto /usr/share/${PN}/lib/node_modules/typescript
	doins -r "${WORKDIR}"/typescript/{lib,package.json,LICENSE.txt,ThirdPartyNoticeText.txt}

	# package.json points bin at lib/cli.mjs, which is meant to be reached
	# through node_modules/.bin; the launcher uses an absolute path instead.
	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		exec node /usr/share/${PN}/lib/cli.mjs "\$@"
	EOF
	dobin "${T}"/${PN}

	dodoc README.md
}
