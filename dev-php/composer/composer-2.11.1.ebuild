# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit optfeature shell-completion

DESCRIPTION="Dependency manager for PHP"
HOMEPAGE="https://getcomposer.org/ https://github.com/composer/composer"
# The release phar bundles every dependency from upstream's composer.lock, so
# nothing is fetched at build time. getcomposer.org serves the same bytes as
# the GitHub release asset.
SRC_URI="https://getcomposer.org/download/${PV}/${PN}.phar -> ${P}.phar"
S="${WORKDIR}"

# Composer and almost all bundled libraries are MIT; marc-mabe/php-enum is
# BSD-3-Clause and composer/ca-bundle ships Mozilla's cacert.pem (MPL-2.0).
LICENSE="MIT BSD MPL-2.0"
SLOT="0"
# A phar is PHP code, not architecture-specific.
KEYWORDS="~amd64"

# composer.json requires ext-filter, ext-hash and ext-json (the last two are
# always built into PHP 8). ssl is required in practice: without ext-openssl
# every download aborts unless the user sets the unsafe disable-tls option.
# ext-curl, ext-zip and ext-zlib are upstream "suggest" entries, see
# pkg_postinst.
RDEPEND="dev-lang/php:*[cli,filter,phar,ssl]"
BDEPEND="dev-lang/php:*[cli,filter,phar]"

src_unpack() {
	# A phar is not an archive unpack() knows; it is installed as fetched.
	:
}

src_compile() {
	# Symfony names the completion function after argv[0]'s basename, so
	# the phar is run under the name the wrapper installs.
	cp "${DISTDIR}/${P}.phar" ${PN} || die

	local -x COMPOSER_ALLOW_SUPERUSER=1 COMPOSER_DISABLE_NETWORK=1
	local -x COMPOSER_HOME="${T}/composer-home"
	php ${PN} --no-interaction --no-ansi completion bash > ${PN}.bash || die
}

src_install() {
	insinto /usr/share/${PN}
	newins "${DISTDIR}/${P}.phar" ${PN}.phar

	cat > "${T}/${PN}" <<-EOF || die
		#!/bin/sh
		exec php /usr/share/${PN}/${PN}.phar "\$@"
	EOF
	dobin "${T}/${PN}"

	newbashcomp ${PN}.bash ${PN}
}

pkg_postinst() {
	optfeature "HTTP transfers through libcurl (faster, parallel)" "dev-lang/php[curl]"
	optfeature "gzip-compressed HTTP responses" "dev-lang/php[zlib]"
	optfeature "extracting zip dists in-process" "dev-lang/php[zip]"
	optfeature "extracting zip dists without ext-zip" app-arch/unzip app-arch/7zip
	optfeature "git sources and VCS repositories" dev-vcs/git
	optfeature "Subversion repositories" dev-vcs/subversion
	optfeature "Mercurial repositories" dev-vcs/mercurial
	optfeature "Fossil repositories" dev-vcs/fossil

	elog "Composer is managed by Portage: 'composer self-update' cannot replace"
	elog "the root-owned /usr/share/${PN}/${PN}.phar. Update it through emerge."
	elog
	elog "glsa-check reports GLSA 202508-06 against every version (<=9999):"
	elog "it records ::gentoo dropping Composer, and its CVEs are fixed since"
	elog "2.6.4. This package is maintained by bentoo and follows upstream's"
	elog "advisories: https://github.com/composer/composer/security/advisories"
	elog "To mark the GLSA as handled: glsa-check --inject 202508-06 (as root)."
}
