# Copyright 1999-2026 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8
# BENTOO-DIVERGENCE: INHERIT - shell-completion, the successor eclass that
# covers zsh and fish alongside bash; ::gentoo still inherits
# bash-completion-r1. newbashcomp below comes from it either way.
inherit go-module shell-completion toolchain-funcs
GIT_COMMIT=c93a4cb9311efc66b90d33ea03f75f2c4120e9b0
GIT_COMMIT_SHORT=${GIT_COMMIT:0:9}

DESCRIPTION="Local kubernetes clusters for learning and development"
HOMEPAGE="https://github.com/kubernetes/minikube https://kubernetes.io"

SRC_URI="https://github.com/kubernetes/minikube/archive/refs/tags/v${PV}.tar.gz -> ${P}.tar.gz
	https://dev.gentoo.org/~zmedico/dist/${P}-deps.tar.xz"

LICENSE="Apache-2.0 BSD BSD-2 CC-BY-4.0 CC-BY-SA-4.0 CC0-1.0 GPL-2 ISC LGPL-3 MIT MPL-2.0 WTFPL-2 ZLIB || ( LGPL-3+ GPL-2 ) || ( Apache-2.0 LGPL-3+ ) || ( Apache-2.0 CC-BY-4.0 )"
SLOT="0"
KEYWORDS="~amd64 ~arm64"
IUSE="libvirt"

# Since 1.38 the kvm2 driver is linked into the minikube binary itself
# (pkg/minikube/registry/drvs/kvm2) and reaches libvirt through dlopen: the
# Makefile builds with -tags libvirt_dlopen, which selects "#cgo LDFLAGS: -ldl"
# instead of "#cgo pkg-config: libvirt" in libvirt.org/go/libvirt.  Nothing
# libvirt-related is needed to compile, so the dependency is runtime-only --
# without it dlopen("libvirt.so.0") fails and only the kvm2 driver is lost.
RDEPEND="libvirt? ( app-emulation/libvirt:=[qemu] )"

# go.mod says "go 1.25.0"; the eclass only floors go at its own default, and
# portage raises a QA notice for the gap.  dev-go/go-bindata is gone from here:
# the Makefile stopped invoking it, and nothing outside a comment and one
# skip-path regex mentions bindata any more.
BDEPEND=">=dev-lang/go-1.25.0"

RESTRICT="test"

src_unpack() {
	default
}

src_prepare() {
	ln -sv ../vendor ./ || die
	default
	sed -e '/export GOTOOLCHAIN/d' -i Makefile || die
}

src_configure() {
	case "${ARCH}" in
		amd64|arm*)
			minikube_arch="${ARCH}" ;;
		ppc64)
			# upstream does not support big-endian ppc64
			minikube_arch="${ARCH}le" ;;
		*)
			die "${ARCH} is not supported" ;;
	esac
	minikube_target="out/minikube-linux-${minikube_arch}"
}

src_compile() {
	# 1.38 deleted cmd/drivers/kvm, so there is no out/docker-machine-driver-kvm2
	# target any more -- asking for it is a hard "No rule to make target" stop.
	COMMIT=${GIT_COMMIT} \
	COMMIT_NO=${GIT_COMMIT} \
	COMMIT_SHORT=${GIT_COMMIT_SHORT} \
	LDFLAGS="" \
	emake "${minikube_target}"
}

src_install() {
	newbin "${minikube_target}" minikube
	dodoc -r site CHANGELOG.md README.md

	if ! tc-is-cross-compiler; then
		"${minikube_target}" completion bash > "${T}/bashcomp" || die
		"${minikube_target}" completion fish > "${T}/fishcomp" || die
		"${minikube_target}" completion zsh > "${T}/zshcomp" || die

		newbashcomp "${T}/bashcomp" minikube
		newfishcomp "${T}/fishcomp" minikube.fish
		newzshcomp "${T}/zshcomp" _minikube
	fi
}

pkg_postinst() {
	elog "You may want to install the following optional dependencies:"
	elog "  app-emulation/virtualbox or app-emulation/virtualbox-bin"
	elog "  sys-cluster/kubectl"

	if use libvirt; then
		elog
		elog "The kvm2 driver no longer ships as a separate"
		elog "docker-machine-driver-kvm2 binary: upstream moved it into the"
		elog "minikube binary in 1.38.  Remove any stale copy left behind by"
		elog "an earlier version, it will not be used:"
		elog "  /usr/bin/docker-machine-driver-kvm2"
	fi
}
