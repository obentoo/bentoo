# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

VERIFY_SIG_OPENPGP_KEY_PATH=/usr/share/openpgp-keys/openssl.org.asc
inherit edo flag-o-matic linux-info sysroot toolchain-funcs
inherit multibuild multilib multilib-build multiprocessing preserve-libs

DESCRIPTION="Robust, full-featured Open Source Toolkit for the Transport Layer Security (TLS)"
HOMEPAGE="https://openssl-library.org/"

MY_P=${P/_/-}

if [[ ${PV} == *9999 ]] ; then
	[[ ${PV} == *.*.9999 ]] && EGIT_BRANCH="openssl-${PV%%.9999}"
	EGIT_REPO_URI="https://github.com/openssl/openssl.git"

	inherit git-r3
else
	inherit verify-sig
	SRC_URI="
		https://github.com/openssl/openssl/releases/download/${MY_P}/${MY_P}.tar.gz
		verify-sig? (
			https://github.com/openssl/openssl/releases/download/${MY_P}/${MY_P}.tar.gz.asc
		)
	"

	if [[ ${PV} != *_alpha* && ${PV} != *_beta* ]] ; then
		KEYWORDS="~amd64"
	fi

	BDEPEND="verify-sig? ( >=sec-keys/openpgp-keys-openssl-20240920 )"
fi

S="${WORKDIR}"/${MY_P}

LICENSE="Apache-2.0"
SLOT="0/$(ver_cut 1)"
IUSE="+asm cpu_flags_x86_sse2 fips ktls +quic rfc3779 sctp static-libs test tls-compression vanilla weak-ssl-ciphers"
RESTRICT="!test? ( test )"

COMMON_DEPEND="
	!<net-misc/openssh-9.2_p1-r3
	tls-compression? ( >=virtual/zlib-1.2.8-r1:=[static-libs(+)?,${MULTILIB_USEDEP}] )
"
BDEPEND+="
	>=dev-lang/perl-5
	sctp? ( >=net-misc/lksctp-tools-1.0.12 )
	test? (
		sys-apps/diffutils
		app-alternatives/bc
		sys-process/procps
	)
"
DEPEND="${COMMON_DEPEND}"
RDEPEND="${COMMON_DEPEND}"
PDEPEND="app-misc/ca-certificates"

MULTILIB_WRAPPED_HEADERS=(
	/usr/include/openssl/configuration.h
)

pkg_setup() {
	if use ktls ; then
		if kernel_is -lt 4 18 ; then
			ewarn "Kernel implementation of TLS (USE=ktls) requires kernel >=4.18!"
		else
			CONFIG_CHECK="~TLS ~TLS_DEVICE"
			ERROR_TLS="You will be unable to offload TLS to kernel because CONFIG_TLS is not set!"
			ERROR_TLS_DEVICE="You will be unable to offload TLS to kernel because CONFIG_TLS_DEVICE is not set!"
			use test && CONFIG_CHECK+=" ~CRYPTO_USER_API_SKCIPHER"

			linux-info_pkg_setup
		fi
	fi

	[[ ${MERGE_TYPE} == binary ]] && return

	if use test && use sctp ; then
		local sctp_auth_status=$(sysctl -n net.sctp.auth_enable 2>/dev/null)
		if [[ -z "${sctp_auth_status}" ]] || [[ ${sctp_auth_status} != 1 ]] ; then
			die "FEATURES=test with USE=sctp requires net.sctp.auth_enable=1!"
		fi
	fi
}

src_prepare() {
	rm -f Makefile || die

	if ! use vanilla ; then
		PATCHES+=(
		)
	fi

	default

	if use test && use sctp && has network-sandbox ${FEATURES} ; then
		einfo "Disabling test '80-test_ssl_new.t' which is known to fail with FEATURES=network-sandbox ..."
		rm test/recipes/80-test_ssl_new.t || die
	fi
}

_openssl_variant() {
	local OPENSSL_VARIANT=${MULTIBUILD_VARIANT}
	mkdir -p "${BUILD_DIR}" || die
	pushd "${BUILD_DIR}" >/dev/null || die
	"$@"
	popd >/dev/null || die
}

openssl_foreach_variant() {
	local MULTIBUILD_VARIANTS=( "${OPENSSL_VARIANTS[@]}" )
	multibuild_foreach_variant _openssl_variant "$@"
}

openssl_run_phase() {
	multilib_foreach_abi openssl_foreach_variant "$@"
}

openssl_is_default_variant() {
	[[ ${OPENSSL_VARIANT} == shared ]] && multilib_is_native_abi
}

src_configure() {
	SSL_CNF_DIR="/etc/ssl"

	tc-is-clang && append-flags -Qunused-arguments

	filter-flags -fstrict-aliasing
	append-flags -fno-strict-aliasing
	filter-lto

	append-flags $(test-flags-CC -Wa,--noexecstack)

	[[ ${CHOST} == *-darwin* ]] || append-atomic-flags
	export LDLIBS="${LIBS}"

	unset APPS
	unset SCRIPTS
	unset CROSS_COMPILE

	tc-export AR CC CXX RANLIB RC

	OPENSSL_VARIANTS=( shared )
	use static-libs && OPENSSL_VARIANTS+=( static )

	openssl_run_phase openssl_src_configure
}

openssl_src_configure() {
	use_ssl() { usex $1 "enable-${2:-$1}" "no-${2:-$1}" " ${*:3}" ; }

	local krb5=$(has_version app-crypt/mit-krb5 && echo "MIT" || echo "Heimdal")

	local sslout=$(bash "${FILESDIR}/gentoo.config-1.0.4")
	einfo "Using configuration: ${sslout:-(openssl knows best)}"

	local myeconfargs=(
		${sslout}

		$(openssl_is_default_variant || echo "no-docs")
		$(use cpu_flags_x86_sse2 || echo "no-sse2")
		enable-camellia
		enable-ec
		enable-ec2m
		enable-sm2
		enable-srp
		$(use elibc_musl && echo "no-async")
		enable-idea
		enable-mdc2
		enable-rc5
		$(use fips && echo "enable-fips")
		$(use quic && echo "enable-quic")
		$(use_ssl asm)
		$(use_ssl ktls)
		$(use_ssl rfc3779)
		$(use_ssl sctp)
		$(use test || echo "no-tests")
		$(use_ssl tls-compression zlib)
		$(use_ssl weak-ssl-ciphers)

		--prefix="${EPREFIX}"/usr
		--openssldir="${EPREFIX}"${SSL_CNF_DIR}
		--libdir=$(get_libdir)

		threads
	)

	if [[ ${OPENSSL_VARIANT} == static ]]; then
		myeconfargs+=( no-module no-shared )
	fi

	edo perl "${S}/Configure" "${myeconfargs[@]}"
}

src_compile() {
	openssl_run_phase openssl_src_compile
}

openssl_src_compile() {
	emake build_sw
	if openssl_is_default_variant; then
		emake build_docs
	fi
}

src_test() {
	openssl_run_phase openssl_src_test
}

openssl_src_test() {
	emake -Onone -j1 HARNESS_JOBS="$(makeopts_jobs)" VFP=1 test
}

openssl_src_install() {
	if [[ ${OPENSSL_VARIANT} == static ]]; then
		dolib.a libcrypto.a libssl.a
		return
	fi

	emake DESTDIR="${D}" -j1 install_sw
	rm "${ED}"/usr/$(get_libdir)/lib{crypto,ssl}.a || die

	if use fips; then
		emake DESTDIR="${D}" -j1 install_fips
		rm "${ED}${SSL_CNF_DIR}"/fipsmodule.cnf || die
	fi

	if openssl_is_default_variant; then
		emake DESTDIR="${D}" -j1 install_ssldirs
		emake DESTDIR="${D}" DOCDIR='$(INSTALLTOP)'/share/doc/${PF} -j1 install_docs
	fi

	multilib_prepare_wrappers
	multilib_check_headers
}

src_install() {
	openssl_run_phase openssl_src_install
	multilib_install_wrappers

	dodoc {AUTHORS,CHANGES,NEWS,README,README-PROVIDERS}.md doc/*.txt doc/${PN}-c-indent.el

	keepdir ${SSL_CNF_DIR}/certs

	dodir /etc/sandbox.d
	echo 'SANDBOX_PREDICT="/dev/crypto"' > "${ED}"/etc/sandbox.d/10openssl

	diropts -m0700
	keepdir ${SSL_CNF_DIR}/private
}

pkg_preinst() {
	if use fips; then
		einfo "Running openssl fipsinstall"
		LD_LIBRARY_PATH="${ED}/usr/$(get_libdir)" \
			sysroot_run_prefixed "${ED}/usr/bin/openssl" fipsinstall \
			-out "${ED}${SSL_CNF_DIR}/fipsmodule.cnf" \
			-module "${ED}/usr/$(get_libdir)/ossl-modules/fips.so" \
			|| die "fipsinstall failed"
	fi

	preserve_old_lib /usr/$(get_libdir)/lib{crypto,ssl}$(get_libname 1) \
		/usr/$(get_libdir)/lib{crypto,ssl}$(get_libname 1.1)
}

pkg_postinst() {
	ebegin "Running 'openssl rehash ${EROOT}${SSL_CNF_DIR}/certs' to rebuild hashes (bug #333069)"
	openssl rehash "${EROOT}${SSL_CNF_DIR}/certs"
	eend $?

	preserve_old_lib_notify /usr/$(get_libdir)/lib{crypto,ssl}$(get_libname 1) \
		/usr/$(get_libdir)/lib{crypto,ssl}$(get_libname 1.1)
}
