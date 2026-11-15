# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# Measured 2026-09-06: every langpack/helppack RPM the TDF mirror serves is
# "PayloadIsXz". Without this, rpm.eclass takes its unset branch and narrows
# BDEPEND to app-arch/rpm2targz alone, forcing that package on anyone who
# already has app-arch/rpm. It is @PRE_INHERIT, so it must precede the inherit.
RPM_COMPRESS_TYPE=xz

inherit rpm

BASE_PV=$(ver_cut 1-3)
MY_PV="${PV/_alpha/.alpha}"
MY_PV="${MY_PV/_beta/.beta}"
MY_PV="${MY_PV/_pre/}"
[[ ${PV} == *alpha* || ${PV} == *beta* ]] && PN_DEV="Dev"
# Pre-release series (alpha/beta/rc, i.e. _pre) are published under testing/
# only; stable/${BASE_PV} does not exist for them at all.
[[ ${PV} == *_alpha* || ${PV} == *_beta* || ${PV} == *_pre* ]] && TESTING_ONLY=1

# BENTOO-DIVERGENCE: KEYWORDS - ~amd64 alone, where ::gentoo keywords six more
# arches. ::gentoo builds the langpacks from source; this ebuild unpacks the
# RPMs the Document Foundation publishes, and the only ones they publish are
# Linux_x86-64 (see SRC_URI). No other arch has a payload to install.
DESCRIPTION="Translations for the Libreoffice suite"
HOMEPAGE="https://www.libreoffice.org"
BASE_SRC_URI_TESTING="https://download.documentfoundation.org/${PN/-l10n/}/testing/${BASE_PV}/rpm"
BASE_SRC_URI_STABLE="https://download.documentfoundation.org/${PN/-l10n/}/stable/${BASE_PV}/rpm"

LICENSE="|| ( LGPL-3 MPL-1.1 )"
SLOT="0"
KEYWORDS="~amd64"
IUSE="offlinehelp"

#
# when changing the language lists, please be careful to preserve the spaces (bug 491728)
#
# "en:en-US" for mapping from Gentoo "en" to upstream "en-US" etc.
# TODO: Try re-add LANGUAGES_HELP=km again (bug #933765)
LANGUAGES_HELP=" am ar ast bg bn-IN bn bo bs ca-valencia ca cs da de dz el en-GB en:en-US en-ZA eo es et eu fi fr gl gu he hi hr hu id is it ja ka ko lo lt lv mk nb ne nl nn om pl pt-BR pt ro ru si sid sk sl sq sv ta tr ug uk vi zh-CN zh-TW "
LANGUAGES="${LANGUAGES_HELP}af as be br brx ckb cy dgo dsb fa fur fy ga gd gug hsb kab kk kmr-Latn kn kok ks lb mai ml mn mni mr my nr nso oc or pa:pa-IN rw sa:sa-IN sat sd sr-Latn sr ss st sw-TZ szl te tg th tn ts tt uz ve vec xh zu "

# Dev (alpha/beta) builds are published only under testing/, named after the
# full MY_PV; stable/ is named after BASE_PV and never carries the Dev suffix.
# Both mirrors must rename to the same distfile, otherwise portage treats them
# as two separate files instead of two sources for one.
lo_uris() {
	local kind=${1} dir=${2}
	local dest="LibreOffice_${MY_PV}_Linux_x86-64_rpm_${kind}_${dir}.tar.gz"

	if [[ -n ${TESTING_ONLY} ]]; then
		echo "${BASE_SRC_URI_TESTING}/x86_64/LibreOffice${PN_DEV}_${MY_PV}_Linux_x86-64_rpm_${kind}_${dir}.tar.gz -> ${dest}"
	else
		echo "${BASE_SRC_URI_STABLE}/x86_64/LibreOffice_${BASE_PV}_Linux_x86-64_rpm_${kind}_${dir}.tar.gz -> ${dest}
			${BASE_SRC_URI_TESTING}/x86_64/LibreOffice_${MY_PV}_Linux_x86-64_rpm_${kind}_${dir}.tar.gz -> ${dest}"
	fi
}

for lang in ${LANGUAGES_HELP}; do
	SRC_URI+=" l10n_${lang%:*}? ( offlinehelp? ( $(lo_uris helppack ${lang#*:}) ) )"
done
for lang in ${LANGUAGES}; do
	if [[ ${lang%:*} != en ]]; then
		SRC_URI+=" l10n_${lang%:*}? ( $(lo_uris langpack ${lang#*:}) )"
	fi
	IUSE+=" l10n_${lang%:*}"
done
unset lang

RDEPEND+="app-text/hunspell"

RESTRICT="strip"

S="${WORKDIR}"

src_prepare() {
	default

	local lang dir rpmdir

	# First remove dictionaries, we want to use system ones.
	find "${S}" -name *dict*.rpm -delete || die "Failed to remove dictionaries"

	for lang in ${LANGUAGES}; do
		# break away if not enabled
		use l10n_${lang%:*} || continue

		dir=${lang#*:}

		# for english we provide just helppack, as translation is always there
		if [[ ${lang%:*} != en ]]; then
			rpmdir="LibreOffice${PN_DEV}_${MY_PV}_Linux_x86-64_rpm_langpack_${dir}/RPMS/"
			[[ -d ${rpmdir} ]] || die "Missing directory: ${rpmdir}"
			rpm_unpack ./${rpmdir}/*.rpm
		fi
		if [[ "${LANGUAGES_HELP}" =~ " ${lang} " ]] && use offlinehelp; then
			rpmdir="LibreOffice${PN_DEV}_${MY_PV}_Linux_x86-64_rpm_helppack_${dir}/RPMS/"
			[[ -d ${rpmdir} ]] || die "Missing directory: ${rpmdir}"
			rpm_unpack ./${rpmdir}/*.rpm
		fi
	done
}

src_configure() { :; }
src_compile() { :; }

src_install() {
	# Dev builds unpack into /opt/libreofficedev<major.minor>, not /opt/libreoffice<major.minor>
	local dir="${S}"/opt/${PN/-l10n/}${PN_DEV,,}$(ver_cut 1-2)/
	# Condition required for people who do not install anything e.g. no l10n
	# or just english with no offlinehelp.
	if [[ -d "${dir}" ]] ; then
		insinto /usr/$(get_libdir)/${PN/-l10n/}/
		doins -r "${dir}"/*
	fi
	# remove extensions that are in l10n for some weird reason
	rm -rf "${ED}"/usr/$(get_libdir)/${PN/-l10n/}/share/extensions/ || \
		die "Failed to remove extensions"
}
