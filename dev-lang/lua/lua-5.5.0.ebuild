# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# NOTE: No Gentoo autotools-patched tarball exists for 5.5 yet
# (see https://gitweb.gentoo.org/proj/lua-patches.git).
# Using upstream tarball; src_compile and src_install are custom
# to handle shared library and slotted installation.
inherit flag-o-matic toolchain-funcs optfeature

DESCRIPTION="A powerful light-weight programming language designed for extending applications"
HOMEPAGE="https://www.lua.org/"
SRC_URI="https://www.lua.org/ftp/${P}.tar.gz"

LICENSE="MIT"
SLOT="5.5"
KEYWORDS="~amd64"
IUSE="+deprecated readline"

DEPEND="
	>=app-eselect/eselect-lua-3
	readline? ( sys-libs/readline:= )
	!dev-lang/lua:0"
RDEPEND="${DEPEND}"
BDEPEND="virtual/pkgconfig"

src_prepare() {
	default

	if use elibc_musl; then
		# locales on musl are non-functional (#834153)
		# https://wiki.musl-libc.org/open-issues.html#Locale-limitations
		sed -e 's|os.setlocale("pt_BR") or os.setlocale("ptb")|false|g' \
			-i tests/literals.lua || die
	fi
}

src_configure() {
	use deprecated && append-cppflags -DLUA_COMPAT_5_4
}

src_compile() {
	# Lua 5.5 removed 'linux-readline' target; 'linux' includes readline.
	local mytarget="linux"
	use readline || mytarget="posix"

	emake \
		CC="$(tc-getCC)" \
		AR="$(tc-getAR) rcu" \
		RANLIB="$(tc-getRANLIB)" \
		MYCFLAGS="${CFLAGS} ${CPPFLAGS} -fPIC -DLUA_USE_LINUX" \
		MYLDFLAGS="${LDFLAGS}" \
		"${mytarget}"

	# Build shared library from the static archive
	pushd src > /dev/null || die
	$(tc-getCC) -shared -o liblua.so \
		-Wl,-soname,liblua-${PV%.*}.so \
		-Wl,--whole-archive liblua.a -Wl,--no-whole-archive \
		${LDFLAGS} -lm -ldl || die "failed to build shared library"
	popd > /dev/null || die
}

src_install() {
	emake \
		INSTALL_TOP="${ED}/usr" \
		INSTALL_LIB="${ED}/usr/$(get_libdir)" \
		INSTALL_MAN="${ED}/usr/share/man/man1" \
		install

	# Shared library
	local sover="${PV%.*}"
	dolib.so "src/liblua.so"
	dosym "liblua.so" "/usr/$(get_libdir)/liblua-${sover}.so"
	dosym "liblua.so" "/usr/$(get_libdir)/liblua${SLOT}.so"

	# Slotted binaries
	mv "${ED}/usr/bin/lua" "${ED}/usr/bin/lua${SLOT}" || die
	mv "${ED}/usr/bin/luac" "${ED}/usr/bin/luac${SLOT}" || die

	# Slotted man pages
	mv "${ED}/usr/share/man/man1/lua.1" "${ED}/usr/share/man/man1/lua${SLOT}.1" || die
	mv "${ED}/usr/share/man/man1/luac.1" "${ED}/usr/share/man/man1/luac${SLOT}.1" || die

	# Slotted headers
	dodir "/usr/include/lua${SLOT}"
	mv "${ED}/usr/include/"*.h "${ED}/usr/include/lua${SLOT}/" || die
	mv "${ED}/usr/include/"*.hpp "${ED}/usr/include/lua${SLOT}/" 2>/dev/null

	# pkg-config
	local pc_file="${T}/lua${SLOT}.pc"
	cat > "${pc_file}" <<-EOF || die
	V=${sover}
	R=${PV}

	prefix=/usr
	INSTALL_BIN=\${prefix}/bin
	INSTALL_INC=\${prefix}/include/lua${SLOT}
	INSTALL_LIB=\${prefix}/$(get_libdir)
	INSTALL_MAN=\${prefix}/share/man/man1
	INSTALL_LMOD=\${prefix}/share/lua/${sover}
	INSTALL_CMOD=\${prefix}/$(get_libdir)/lua/${sover}
	exec_prefix=\${prefix}
	libdir=\${exec_prefix}/$(get_libdir)
	includedir=\${prefix}/include/lua${SLOT}

	Name: Lua
	Description: An Extensible Extension Language
	Version: ${PV}
	Requires:
	Libs: -L\${libdir} -llua -lm -ldl
	Cflags: -I\${includedir}
	EOF
	insinto "/usr/$(get_libdir)/pkgconfig"
	doins "${pc_file}"

	# Cleanup
	find "${ED}" -name '*.a' -delete || die
	find "${ED}" -name '*.la' -delete || die
}

pkg_postinst() {
	eselect lua set --if-unset "${PN}${SLOT}"

	optfeature "Lua support for Emacs" app-emacs/lua-mode
}
