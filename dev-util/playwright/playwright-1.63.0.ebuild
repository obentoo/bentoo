# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="Automate Chromium, Firefox and WebKit browsers with a single API"
HOMEPAGE="https://playwright.dev/
	https://github.com/microsoft/playwright/
	https://registry.npmjs.org/playwright/"

# playwright depends on playwright-core (same version, no deps of its own) and
# does not bundle it, so both npm tarballs have to be fetched up front: the
# merge itself runs with network-sandbox and npm cannot reach the registry.
SRC_URI="
	https://registry.npmjs.org/${PN}/-/${P}.tgz
		-> ${P}.npm.tgz
	https://registry.npmjs.org/${PN}-core/-/${PN}-core-${PV}.tgz
		-> ${PN}-core-${PV}.npm.tgz
"
S="${WORKDIR}/package"

LICENSE="Apache-2.0"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
# Pure JavaScript plus a WASM codec and data files, no ELF objects: nothing
# arch-specific is installed. The browser binaries are downloaded at runtime by
# "playwright install", exactly as with the upstream npm package.
RESTRICT="test"

RDEPEND="
	>=net-libs/nodejs-20
	!dev-python/playwright-bin
"
BDEPEND="
	net-libs/nodejs[npm]
"

DOCS=( NOTICE README.md )

src_unpack() {
	# Both tarballs extract into "package/", so unpacking them together would
	# let playwright-core silently overwrite playwright's own README/NOTICE.
	# Only the main package is unpacked (for DOCS); npm installs straight from
	# ${DISTDIR}.
	unpack "${P}.npm.tgz"
}

src_compile() {
	# Skip, nothing to compile here.
	:
}

src_install() {
	# Never let npm touch the invoking user's ${HOME}/.npm during a merge.
	local -x HOME="${T}"
	local -x npm_config_cache="${T}/npm-cache"

	local -a my_npm_opts=(
		--prefix="${ED}/usr"
		--audit=false
		--color=false
		--progress=false
		--foreground-scripts
		--fund=false
		--global
		--offline
		--omit=dev
		--omit=optional
		--update-notifier=false
		--verbose
	)

	# playwright-core is passed alongside playwright so npm resolves the
	# dependency from the local tarball instead of the registry; both end up as
	# siblings in the global node_modules, where Node's resolution algorithm
	# finds playwright-core when playwright requires it. --omit=optional drops
	# the darwin-only fsevents optional dependency, whose metadata is not
	# available offline either.
	npm "${my_npm_opts[@]}" install \
		"${DISTDIR}/${PN}-core-${PV}.npm.tgz" \
		"${DISTDIR}/${P}.npm.tgz" || die "npm install failed"

	einstalldocs
}
