# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

DESCRIPTION="PHP completion, refactoring and introspection tool and language server"
HOMEPAGE="https://phpactor.readthedocs.io/ https://github.com/phpactor/phpactor"
# The release asset is a Humbug Box phar with every Composer dependency
# inside it, so nothing is fetched at build time.
SRC_URI="https://github.com/phpactor/phpactor/releases/download/${PV}/${PN}.phar -> ${P}.phar"
S="${WORKDIR}"

# phpactor itself is MIT; the phar also carries jetbrains/phpstorm-stubs
# (Apache-2.0) and twig/twig, sebastian/diff, phpactor/phly-event-dispatcher
# (BSD-3-Clause). Everything else bundled is MIT (upstream composer.lock).
LICENSE="MIT Apache-2.0 BSD"
SLOT="0"
# A phar is PHP code, not architecture-specific.
KEYWORDS="~amd64"

# The phar runs Box's requirement checker before phpactor itself and aborts
# unless every extension it lists is loaded:
#   zlib      - every file in the phar is gzip-compressed
#   posix, tokenizer          - phpactor (composer.json ext-*)
#   filter, iconv, ssl(openssl) - amphp/dns, polyfill-mbstring, amphp/socket
# unicode (ext-mbstring) is not checked by Box, because the phar bundles
# symfony/polyfill-mbstring, but composer.json requires it, so it is kept.
# json and date are always built into PHP 8.
RDEPEND="
	>=dev-lang/php-8.2:*[cli,filter,iconv,phar,posix,ssl,tokenizer,unicode,zlib]
"

src_unpack() {
	# A phar is not an archive unpack() knows; it is installed as fetched.
	:
}

src_install() {
	insinto /usr/share/${PN}
	newins "${DISTDIR}"/${P}.phar ${PN}.phar

	cat > "${T}"/${PN} <<-EOF || die
		#!/bin/sh
		exec php /usr/share/${PN}/${PN}.phar "\$@"
	EOF
	dobin "${T}"/${PN}
}
